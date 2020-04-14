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

extension Codec.FFmpeg.Encoder {
    
    class MuxerSession: NSObject {
        
        private let fmtCtx: UnsafeMutablePointer<AVFormatContext>
        
        private var videoStream: UnsafeMutablePointer<AVStream>?
        private var audioStream: UnsafeMutablePointer<AVStream>?
        
        private var audioSession: AudioSession? = nil
        private var videoSession: VideoSession? = nil
        
        private var currVideoPts: Int64 = ZeroPts
        private var currAudioPts: Int64 = ZeroPts
        
        private let flags: MuxStreamFlags
        
        internal lazy var muxingQueue: DispatchQueue = {
            DispatchQueue.init(label: "com.zdnet.ffmpeg.encoder.muxing.Queue")
        }()
        
        var onMuxedData: MuxedDataCallback? = nil
        
        init(flags: MuxStreamFlags, format: Codec.FFmpeg.Encoder.MuxFormat, onMuxed: @escaping Codec.FFmpeg.Encoder.MuxedDataCallback) throws {
            
            var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
            guard avformat_alloc_output_context2(&fmtCtx, nil, format, nil) >= 0  else {
                throw NSError.error(ErrorDomain, reason: "Failed to create output context.")!
            }
            self.fmtCtx = fmtCtx!
            self.onMuxedData = onMuxed
            self.flags = flags
            super.init()
            weak var weakSelf = self
            withUnsafeMutablePointer(to: &weakSelf) { [unowned self] (ptr) in
                let ioBufferSize: Int = 512*1024 //32768
                let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: ioBufferSize)
                let writable: Int = 1
                let ioCtx = avio_alloc_context(buff, Int32(ioBufferSize), Int32(writable), ptr, nil, muxerCallback, nil)
                self.fmtCtx.pointee.pb = ioCtx
                self.fmtCtx.pointee.flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_NOFILE | AVFMT_FLAG_FLUSH_PACKETS
            }
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
        
        let session = try Codec.FFmpeg.Encoder.VideoSession.init(config: config)
        let timebase = session.codecCtx!.pointee.time_base
        self.videoSession = session
        self.videoStream = try self.addStream(codecCtx: session.codecCtx!)
        self.videoSession!.onEncodedPacket = { [unowned self] (packet, error) in
            if packet != nil {
                self.muxingQueue.async { [unowned self] in
                    self.currVideoPts = packet!.pointee.pts
                    if self.currentMuxingStream() == .Video {
                        if let err = self.muxer(packet: packet!, stream: self.videoStream!, timebase: timebase) {
                            self.onMuxedData?(nil, err)
                        }
                    }
                    av_packet_unref(packet)
                }
            }else {
                self.onMuxedData?(nil, error)
            }
        }
    }
    
    func addAudioStream(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        
        let session = try Codec.FFmpeg.Encoder.AudioSession.init(in: desc, config: config)
        let timebase = session.codecCtx!.pointee.time_base
        self.audioSession = session
        self.audioStream = try self.addStream(codecCtx: session.codecCtx!)
        self.audioSession!.onEncodedPacket = { [unowned self] (packet, error) in
            if packet != nil {
                self.muxingQueue.async { [unowned self] in
                    self.currAudioPts = packet!.pointee.pts
                    if self.currentMuxingStream() == .Audio {
                        if let err = self.muxer(packet: packet!, stream: self.audioStream!, timebase: timebase) {
                            self.onMuxedData?(nil, err)
                        }
                    }
                    av_packet_unref(packet)
                }
                
            }else {
                self.onMuxedData?(nil, error)
            }
        }
    }
    
    func muxingVideo(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double) throws {
        //由于人对声音的敏锐程度远高于视觉（eg: 视觉有视网膜影像停留机制）,所以如果需要合成音频流，则必须确保视频流在音频流后合成，以确保音视频同步。
        if self.flags.contains(.Audio) && self.currAudioPts <= ZeroPts {
            return
        }
        try self.videoSession?.encode(bytes: bytes, size: size, displayTime: displayTime)
    }
    
    func muxingAudio(bytes: UnsafeMutablePointer<UInt8>, size: Int32) throws {
        try self.audioSession?.encode(bytes: bytes, size: size)
    }
   
}

private
extension Codec.FFmpeg.Encoder.MuxerSession {
    enum MuxingStream {
        case None
        case Audio
        case Video
    }
    
    func currentMuxingStream() -> MuxingStream {
        
        guard let vCodecCtx = self.videoSession?.codecCtx, let aCodecCtx = self.audioSession?.codecCtx else {
            return .None
        }
        
        //The both of two methods are the same thing
        //Method One:
           /*
            let vCurTime = Double(self.videoNextPts) * av_q2d(vCodecCtx.pointee.time_base)
            let aCurTime = Double(self.audioNextPts) * av_q2d(aCodecCtx.pointee.time_base)
            
            if vCurTime <= aCurTime {
                print("V: \(vCurTime) < A: \(aCurTime)")
                return .video
            }else {
                print("V: \(vCurTime) > A: \(aCurTime)")
                return .audio
            }
            */
        //Method two:
        let ret = av_compare_ts(self.currVideoPts, vCodecCtx.pointee.time_base, self.currAudioPts, aCodecCtx.pointee.time_base)
        print("vPts \(self.currVideoPts) - aPts: \(self.currAudioPts)")
        if ret <= 0 /*vCurTime <= aCurTime*/ {
            return .Video
        }else {
            return .Audio
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
        
        stream.pointee.id = Int32(fmtCtx.pointee.nb_streams - 1)
        
        return stream
    }
    
    func addHeader() throws {
        guard avformat_write_header(fmtCtx, nil) >= 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to write output header.")!
        }
    }
    
    func addTrailer() throws {
        guard av_write_trailer(fmtCtx) >= 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to write output trailer.")!
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



