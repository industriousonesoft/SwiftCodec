//
//  MuxSession.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

private let ErrorDomain = "FFmpeg:Muxer"
private let ZeroPts: Int64 = 0


private typealias MuxFormat = String
fileprivate extension MuxFormat {
    static let mpegts: String = "mpegts"
}

extension Codec.FFmpeg.Encoder {
    
    class MuxerSession: NSObject {
        
        private var fmtCtx: UnsafeMutablePointer<AVFormatContext>
        
        private var videoStream: UnsafeMutablePointer<AVStream>?
        private var audioStream: UnsafeMutablePointer<AVStream>?
        
        private var audioSession: AudioSession? = nil
        private var videoSession: VideoSession? = nil
        
        private var currVideoPts: Int64 = ZeroPts
        private var currAudioPts: Int64 = ZeroPts
        
        private var displayTimeBase: Double = 0
        
        private var flags: MuxStreamFlags = []
        
        private var muxingQueue: DispatchQueue
        
        var onMuxedData: MuxedDataCallback? = nil
        
        init(onMuxed: @escaping Codec.FFmpeg.Encoder.MuxedDataCallback, queue: DispatchQueue? = nil) throws {
            
            var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
            guard avformat_alloc_output_context2(&fmtCtx, nil, MuxFormat.mpegts, nil) >= 0  else {
                throw NSError.error(ErrorDomain, reason: "Failed to create output context.")!
            }
            self.fmtCtx = fmtCtx!
            self.onMuxedData = onMuxed
            self.flags = []
            self.muxingQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.MuxerSession.muxing.Queue")
            super.init()
            let ioBufferSize: Int = 512*1024 //32768
            let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: ioBufferSize)
            let writable: Int = 1
            let ioCtx = avio_alloc_context(buff, Int32(ioBufferSize), Int32(writable), unsafeBitCast(self, to: UnsafeMutableRawPointer.self), nil, muxerCallback, nil)
            self.fmtCtx.pointee.pb = ioCtx
            self.fmtCtx.pointee.flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_NOFILE | AVFMT_FLAG_FLUSH_PACKETS
        }
        
        deinit {
            av_write_trailer(self.fmtCtx)
            if let pb = self.fmtCtx.pointee.pb, self.fmtCtx.pointee.flags & AVFMT_NOFILE == 0 {
                if let buff = pb.pointee.buffer {
                    free(buff)
                    pb.pointee.buffer = nil
                }
                avio_close(pb)
                self.fmtCtx.pointee.pb = nil
            }
            avformat_free_context(self.fmtCtx)
        }
    }
}

extension Codec.FFmpeg.Encoder.MuxerSession {
    
    func addVideoStream(config: Codec.FFmpeg.Video.Config) throws {
        
        let session = try Codec.FFmpeg.Encoder.VideoSession.init(config: config, queue: self.muxingQueue)
        self.flags.insert(.Video)
        self.videoSession = session
        self.videoStream = try self.addStream(codecCtx: session.codecCtx!)
  
    }
    
    func addAudioStream(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        
        let session = try Codec.FFmpeg.Encoder.AudioSession.init(in: desc, config: config, queue: self.muxingQueue)
        self.flags.insert(.Audio)
        self.audioSession = session
        self.audioStream = try self.addStream(codecCtx: session.codecCtx!)
    }
    
    func muxingVideo(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double) {
        //如果同时合成音视频，则确保先合成音频再合成视频
        if self.flags.both && self.currAudioPts == ZeroPts {
            return
        }
        //Only Video
        if self.currVideoPts == ZeroPts && self.flags.videoOnly {
            self.addHeader()
        }
        self.videoSession?.encode(bytes: bytes, size: size, displayTime: displayTime, onEncoded: { [unowned self] (packet, error) in
            if packet != nil {
                self.currVideoPts = packet!.pointee.pts
                if self.couldToMuxVideo() {
                    print("muxing video...")
                    if let err = self.muxer(packet: packet!, stream: self.videoStream!, timebase: self.videoSession!.codecCtx!.pointee.time_base) {
                        self.onMuxedData?(nil, err)
                    }
                }
                av_packet_unref(packet!)
            }else {
                self.onMuxedData?(nil, error)
            }
        })
        
    }
    
    func muxingAudio(bytes: UnsafeMutablePointer<UInt8>, size: Int32, displayTime: Double) {
        if self.currAudioPts == ZeroPts {
            self.addHeader()
        }
        self.audioSession?.encode(bytes: bytes, size: size, onEncoded: { [unowned self] (packet, error) in
            if packet != nil {
                //由于人对声音的敏锐程度远高于视觉（eg: 视觉有视网膜影像停留机制）,所以如果需要合成音频流，则必须确保音频流优先合成，而视频流则根据相关计算插入。
                self.currAudioPts = packet!.pointee.pts
                print("muxing audio...")
                if let err = self.muxer(
                    packet: packet!,
                    stream: self.audioStream!,
                    timebase: self.audioSession!.codecCtx!.pointee.time_base)
                {
                    self.onMuxedData?(nil, err)
                }
                av_packet_unref(packet)
            }else {
                self.onMuxedData?(nil, error)
            }
        })
    }
   
}

private
extension Codec.FFmpeg.Encoder.MuxerSession {
   
    func couldToMuxVideo() -> Bool {
       
        if self.flags.videoOnly {
            return false
        }else if self.flags.videoOnly {
            return true
        //Both
        }else if self.flags.both {
            
            guard let vCodecCtx = self.videoSession?.codecCtx,
                let aCodecCtx = self.audioSession?.codecCtx else {
                return false
            }
            //The both of two methods are the same thing
            //Method One:
            /*
            let vCurTime = Double(self.currVideoPts) * av_q2d(vCodecCtx.pointee.time_base)
            let aCurTime = Double(self.currAudioPts) * av_q2d(aCodecCtx.pointee.time_base)
                
            if vCurTime <= aCurTime {
                print("V: \(vCurTime) < A: \(aCurTime)")
                return true
            }else {
                print("V: \(vCurTime) > A: \(aCurTime)")
                return false
            }
               */
            //Method two:
            
            let ret = av_compare_ts(self.currVideoPts, vCodecCtx.pointee.time_base, self.currAudioPts, aCodecCtx.pointee.time_base)
            print("ret: \(ret) - vPts \(self.currVideoPts) - aPts: \(self.currAudioPts)")
            return ret <= 0 ? true : false
        }else {
            return false
        }
    }
}

private
extension Codec.FFmpeg.Encoder.MuxerSession {
    
    func addStream(codecCtx: UnsafeMutablePointer<AVCodecContext>) throws -> UnsafeMutablePointer<AVStream> {
      
        guard let stream = avformat_new_stream(self.fmtCtx, codecCtx.pointee.codec) else {
            throw NSError.error(ErrorDomain, reason: "Failed to create video staream.")!
        }
        
        guard avcodec_parameters_from_context(stream.pointee.codecpar, codecCtx) >= 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to initialize video staream.")!
        }
        
        stream.pointee.id = Int32(self.fmtCtx.pointee.nb_streams - 1)
        
        return stream
    }
    
    func addHeader() {
        self.muxingQueue.async { [unowned self] in
            if avformat_write_header(self.fmtCtx, nil) < 0 {
                self.onMuxedData?(nil, NSError.error(ErrorDomain, reason: "Failed to write output header.")!)
            }
        }
        
    }
    
    func addTrailer() {
        self.muxingQueue.async { [unowned self] in
            if av_write_trailer(self.fmtCtx) < 0 {
                self.onMuxedData?(nil, NSError.error(ErrorDomain, reason: "Failed to write output trailer.")!)
            }
        }
    }
    
    func muxer(packet: UnsafeMutablePointer<AVPacket>, stream: UnsafeMutablePointer<AVStream>, timebase: AVRational) -> Error? {
        
        av_packet_rescale_ts(packet, timebase, stream.pointee.time_base)
        packet.pointee.stream_index = stream.pointee.index
        
        /**
        * Write a packet to an output media file ensuring correct interleaving.
        *
        * @return 0 on success, a negative AVERROR on error. Libavformat will always
        *         take care of freeing the packet, even if this function fails.
        *
        */
        let ret = av_interleaved_write_frame(self.fmtCtx, packet)
        
        return ret == 0 ? nil : NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when muxing video.")!
    }
}

private
func muxerCallback(opaque: UnsafeMutableRawPointer?, buff: UnsafeMutablePointer<UInt8>?, buffSize :Int32) -> Int32 {

    if buff != nil && buffSize > 0 {
        if opaque != nil {
            let encodedData = unsafeBitCast(malloc(Int(buffSize)), to: UnsafeMutablePointer<UInt8>.self)
            memcpy(encodedData, buff, Int(buffSize))
            let session = unsafeBitCast(opaque, to: Codec.FFmpeg.Encoder.MuxerSession.self)
            session.onMuxedData?((encodedData, buffSize), nil)
        }
    }
    
    return 0
}



