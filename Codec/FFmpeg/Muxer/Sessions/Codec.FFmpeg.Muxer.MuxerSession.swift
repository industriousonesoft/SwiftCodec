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

extension Codec.FFmpeg.Muxer {
    
    class MuxerSession {
        
        private var fmtCtx: UnsafeMutablePointer<AVFormatContext>
        
        private var videoStream: UnsafeMutablePointer<AVStream>?
        private var audioStream: UnsafeMutablePointer<AVStream>?
        
        private var audioSession: Codec.FFmpeg.Encoder.AudioSession? = nil
        private var videoSession: Codec.FFmpeg.Encoder.VideoSession? = nil
        
        private var currVideoPts: Int64 = ZeroPts
        private var currAudioPts: Int64 = ZeroPts
        
        private var displayTimeBase: Double = 0
        
        let flags: StreamFlags
        let mode: MuxingMode
        
        private var muxingQueue: DispatchQueue
        
        private var isToMuxingVideo: Bool = false
        
        var onMuxedData: MuxedDataCallback? = nil
        
        init(mode: MuxingMode, flags: StreamFlags, onMuxed: @escaping MuxedDataCallback, queue: DispatchQueue? = nil) throws {
            
            var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
            guard avformat_alloc_output_context2(&fmtCtx, nil, MuxFormat.mpegts, nil) >= 0  else {
                throw NSError.error(ErrorDomain, reason: "Failed to create output context.")!
            }
            self.fmtCtx = fmtCtx!
            self.mode = mode
            self.flags = flags
            self.onMuxedData = onMuxed
            self.muxingQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.MuxerSession.muxing.Queue")
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

//MARK: - Stream Manager
extension Codec.FFmpeg.Muxer.MuxerSession {
    
    func setVideoStream(config: Codec.FFmpeg.Video.Config) throws {
        
        guard self.flags.contains(.Video) else {
            throw NSError.error(ErrorDomain, reason: "Muxer not support to mux video.")!
        }
        
        guard self.videoStream == nil else {
            throw NSError.error(ErrorDomain, reason: "Video stream is set.")!
        }
        
        let session = try Codec.FFmpeg.Encoder.VideoSession.init(config: config, queue: self.muxingQueue)
        self.videoSession = session
        self.videoStream = try self.addStream(codecCtx: session.codecCtx!)
        //Add ts header when all stream set
        if self.flags.contains(.Audio) && self.audioStream != nil {
            self.addHeader()
        }else if self.flags.videoOnly {
            self.addHeader()
        }
    }
    
    func setAudioStream(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        guard self.flags.contains(.Audio) else {
            throw NSError.error(ErrorDomain, reason: "Muxer not support to mux audio.")!
        }
        
        guard self.audioSession == nil else {
            throw NSError.error(ErrorDomain, reason: "Video stream is set.")!
        }
        
        let session = try Codec.FFmpeg.Encoder.AudioSession.init(in: desc, config: config)
        self.audioSession = session
        self.audioStream = try self.addStream(codecCtx: session.codecCtx!)
        //Add ts header when all stream set
        if self.flags.contains(.Video) && self.videoStream != nil {
            self.addHeader()
        }else if self.flags.audioOnly {
            self.addHeader()
        }
    }

}

//MARK: - Muxing
extension Codec.FFmpeg.Muxer.MuxerSession {
    
    func muxingVideo(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onScaled: @escaping Codec.FFmpeg.Encoder.ScaledCallback) {
        //如果同时合成音视频，则确保先合成音频再合成视频
        if self.flags.both && self.currAudioPts == ZeroPts {
            return
        }
        self.videoSession?.encode(bytes: bytes, size: size, displayTime: displayTime, onScaled: onScaled, onEncoded: { [unowned self] (packet, error) in
            //此处如果不clone一次，会出现野指针错误。原因在于packet相关内存是由ffmepg内部函数管理，作用域就在当前{}，即便是muxingQueue捕获后也只是引用计数加1，packet中的数据内存还是会被释放
//                let newPacket = av_packet_clone(packet)
//                av_packet_unref(packet!)
//            self.muxingQueue.async { [unowned self] in
                if packet != nil {
                    self.currVideoPts = packet!.pointee.pts
                    if self.mode == .Dump {
                        //为了保证延时，不能合成时则丢弃掉当前视频帧
                        //如果不考虑延时，可以采用类似音频的处理方式，对视频帧进行缓存，即需即取
                        if self.isToMuxingVideo == true {
//                            print("muxing video...")
                            if let err = self.muxer(packet: packet!, stream: self.videoStream!, timebase: self.videoSession!.codecCtx!.pointee.time_base) {
                                self.onMuxedData?(nil, err)
                            }
                            self.isToMuxingVideo = false
                        }else {
                            self.muxingAudio()
                        }
                    }else if self.mode == .RealTime {
                        //为了保证延时，不能合成时则丢弃掉当前视频帧
                        if self.couldToMuxVideo() {
//                            print("muxing video...")
                            if let err = self.muxer(packet: packet!, stream: self.videoStream!, timebase: self.videoSession!.codecCtx!.pointee.time_base) {
                                self.onMuxedData?(nil, err)
                            }
                        }
                    }
                    av_packet_unref(packet!)
                }else {
                    self.onMuxedData?(nil, error)
                }
//            }
        })
    }
    
    //由于人对声音的敏锐程度远高于视觉（eg: 视觉有视网膜影像停留机制）,所以如果需要合成音频流，则必须确保音频流优先合成，而视频流则根据相关计算插入。
    func muxingAudio(bytes: UnsafeMutablePointer<UInt8>, size: Int32, displayTime: Double) {
     
        if self.mode == .Dump {
            //音频优先合成，确保音频的连续性，但是视频可能会出现比较严重的掉帧情况
            self.audioSession?.write(bytes: bytes, size: size, onFinished: { [unowned self] (error) in
                if error != nil {
                    self.onMuxedData?(nil, error)
                }else {
                    self.muxingQueue.async { [unowned self] in
                        if self.couldToMuxVideo() == false &&
                            self.isToMuxingVideo == false {
                            self.muxingAudio()
                        }else {
                            self.isToMuxingVideo = true
                            print("Audio: could to mux video...")
                        }
                    }
                }
            })
        }else if self.mode == .RealTime {
            //FIXME: 根据音视频编码速度进行合成，音频可能出现杂音，频率不高但是3分钟左右的长度基本上可重现，具体原因不清楚
            self.audioSession?.encode(bytes: bytes, size: size, onEncoded: { [unowned self] (packet, error) in
                if packet != nil {
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
}

private
extension Codec.FFmpeg.Muxer.MuxerSession {
   
    func couldToMuxVideo() -> Bool {
       
        if self.flags.audioOnly {
            return false
        }else if self.flags.videoOnly {
            return true
        //Both
        }else if self.flags.both {
            
            guard let vCodecCtx = self.videoSession?.codecCtx,
                let aCodecCtx = self.audioSession?.codecCtx else {
                return false
            }
            //优先合成音频
            if self.currAudioPts == 0 {
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

    func muxingAudio() {
        
        self.audioSession?.readAndEncode { [unowned self] (packet, error) in
            let newPacket = av_packet_clone(packet)
            av_packet_unref(packet!)
            self.muxingQueue.async { [unowned self] in
                if newPacket != nil {
                    //由于人对声音的敏锐程度远高于视觉（eg: 视觉有视网膜影像停留机制）,所以如果需要合成音频流，则必须确保音频流优先合成，而视频流则根据相关计算插入。
                    self.currAudioPts = newPacket!.pointee.pts
                    print("muxing audio...")
                    if let err = self.muxer(
                        packet: newPacket!,
                        stream: self.audioStream!,
                        timebase: self.audioSession!.codecCtx!.pointee.time_base)
                    {
                        self.onMuxedData?(nil, err)
                    }
                    av_packet_unref(newPacket)
                }else {
                    self.onMuxedData?(nil, error)
                }
            }
        }
    }

    
}


private
extension Codec.FFmpeg.Muxer.MuxerSession {
    
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
            let session = unsafeBitCast(opaque, to: Codec.FFmpeg.Muxer.MuxerSession.self)
            session.onMuxedData?((encodedData, buffSize), nil)
        }
    }
    
    return 0
}



