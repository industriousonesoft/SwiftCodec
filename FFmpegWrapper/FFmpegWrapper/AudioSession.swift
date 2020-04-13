//
//  AudioSession.swift
//  FFmpegWrapper
//
//  Created by caowanping on 2020/1/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CoreAudio
import CFFmpeg
import FFmepgWrapperOCBridge

//MARK: - AudioDescription
public struct FFmpegAudioDescription: Equatable {
    
    public enum SampleFMT {
        case S16
        case S16P
        case FLT
        case FLTP
        
        public func toAVSampleFormat() -> AVSampleFormat {
            switch self {
            case .S16:
                return AVSampleFormat(AV_SAMPLE_FMT_S16.rawValue)
            case .S16P:
                return AVSampleFormat(AV_SAMPLE_FMT_S16P.rawValue)
            case .FLT:
                return AVSampleFormat(AV_SAMPLE_FMT_FLT.rawValue)
            case .FLTP:
                return AVSampleFormat(AV_SAMPLE_FMT_FLTP.rawValue)
            }
        }
    }
    
    public var sampleRate: Int32
    public var channels: Int32
    public var bitsPerChannel: Int32
    public var sampleFormat: SampleFMT
    
    public func sampleFMT(from flags: AudioFormatFlags) -> SampleFMT? {
        if (flags & kAudioFormatFlagIsFloat) != 0 && (flags & kAudioFormatFlagIsNonInterleaved) != 0 {
            return .FLTP
        }else if (flags & kAudioFormatFlagIsFloat) != 0 && (flags & kAudioFormatFlagIsPacked) != 0 {
            return .FLT
        }else if (flags & kAudioFormatFlagIsSignedInteger) != 0 && (flags & kAudioFormatFlagIsPacked) != 0 {
            return .S16
        }else if (flags & kAudioFormatFlagIsSignedInteger) != 0 && (flags & kAudioFormatFlagIsNonInterleaved) != 0 {
            return .S16P
        }else {
            return nil
        }
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.sampleRate == rhs.sampleRate &&
                lhs.channels == rhs.channels &&
                lhs.bitsPerChannel == rhs.bitsPerChannel &&
                lhs.sampleFormat == rhs.sampleFormat
    }
}

//MARK: - AudioDescription
public struct FFmpegEncoderConfig {
    
    public enum CodecType {
        case MP2
        public func toAVCodecID() -> AVCodecID {
            switch self {
            case .MP2:
                return AV_CODEC_ID_MP2
            }
        }
    }
    
    public var codec: CodecType
    public var bitRate: Int64
    public var desc: FFmpegAudioDescription
}

//MARK: - FFmpegAudioSession
public class FFmpegAudioSession: NSObject {
    
    public var inDesc: FFmpegAudioDescription?
    public var config: FFmpegEncoderConfig?
    
    private var encodec:  UnsafeMutablePointer<AVCodec>?
    private var encodecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var encodeFifo: OpaquePointer?
    
    private var encodeInFrame: UnsafeMutablePointer<AVFrame>?
    private var convertOutSampleBuffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
    
    private var swrCtx: OpaquePointer?
    
    private var resampleDstFrameSize: Int32 = 0
    private var audioSampleCount: Int64 = 0
    private var audioNextPts: Int64 = 0
    
    public override init() {
        super.init()
    }
    
}

extension FFmpegAudioSession {
    
    public func addEncoder(in desc: FFmpegAudioDescription, config: FFmpegEncoderConfig) -> Error? {
        
        self.inDesc = desc
        self.config = config
        
        var error: NSError? = nil
        
        defer {
            if error != nil {
                self.removeEncoder()
            }
        }
        
        //Create a aduo converter if neccessary
        if desc != config.desc, let err = self.createConverter(inDesc: desc, outDesc: config.desc) {
            error = err as NSError
            return error
        }
        
        //Codec
        let codecId: AVCodecID = config.codec.toAVCodecID()
        if let codec = avcodec_find_encoder(codecId) {
            self.encodec = codec
        }else {
            error = NSError.error(self.className, reason: "Can not create audio codec...")
            return error
        }
        
        //Codec Context
        if let context = avcodec_alloc_context3(self.encodec) {
            context.pointee.codec_id = codecId
            context.pointee.codec_type = AVMEDIA_TYPE_AUDIO
            context.pointee.sample_fmt = config.desc.sampleFormat.toAVSampleFormat()//AV_SAMPLE_FMT_S16
            context.pointee.channel_layout = self.selectChannelLayout(codec: self.encodec!) ?? UInt64(av_get_default_channel_layout(config.desc.channels))//UInt64(AV_CH_LAYOUT_STEREO)
            context.pointee.sample_rate = self.selectSampleRate(codec: self.encodec!) ?? config.desc.sampleRate//44100
            context.pointee.channels = config.desc.channels//2
            context.pointee.bit_rate = 64000 //128kbps
            context.pointee.time_base.num = 1
            context.pointee.time_base.den = config.desc.sampleRate
            self.encodecCtx = context
        }else {
            error = NSError.error(self.className, reason: "Can not create audio codec context...")
            return error
        }
        
        //encode in frame
         if let frame = av_frame_alloc() {
            frame.pointee.nb_samples = self.encodecCtx!.pointee.frame_size
            frame.pointee.channel_layout = self.encodecCtx!.pointee.channel_layout
            frame.pointee.format = self.encodecCtx!.pointee.sample_fmt.rawValue
            frame.pointee.sample_rate = self.encodecCtx!.pointee.sample_rate
           
            if av_frame_get_buffer(frame, 0) < 0 {
                error = NSError.error(self.className, reason: "Can not create audio codec in frame...")
                return error
            }
            self.encodeInFrame = frame
        }
        
        //看jsmpeg中mp2解码器代码，mp2格式对应的frame_size（nb_samples）似乎是定值：1152
        if avcodec_open2(self.encodecCtx!, self.encodec!, nil) < 0 {
            error = NSError.error(self.className, reason: "Can not open audio avcodec...")
            return error
        }
        
        //fifo
        if let fifo = self.encodeFIFO(of: self.encodecCtx!) {
            self.encodeFifo = fifo
        }else {
            error = NSError.error(self.className, reason: "Can not alloc audio fifo...")
            return error
        }
        
        return nil
    }
    
    public func removeEncoder() {
    
        if let swr = self.swrCtx {
            swr_close(swr)
            swr_free(&self.swrCtx)
            self.swrCtx = nil
        }
        if let context = self.encodecCtx {
            avcodec_close(context)
            avcodec_free_context(&self.encodecCtx)
            self.encodecCtx = nil
        }
        if let fifo = self.encodeFifo {
            av_audio_fifo_free(fifo)
            self.encodeFifo = nil
        }
        if self.encodeInFrame != nil {
            av_frame_free(&self.encodeInFrame)
            self.encodeInFrame = nil
        }
        
        self.freeSampleBuffer()
    
    }
    
    private func selectSampleRate(codec: UnsafeMutablePointer<AVCodec>) -> Int32? {
        //supported_samplerates is a Int32 array contains all the supported samplerate
        guard let ptr: UnsafePointer<Int32> = codec.pointee.supported_samplerates else {
            return nil
        }
        var bestSamplerate: Int32 = 0
        var index: Int = 0
        var cur = ptr.advanced(by: index).pointee
        while cur != 0 {
            if (bestSamplerate == 0 || abs(44100 - cur) < abs(44100 - bestSamplerate)) {
                bestSamplerate = cur
            }
            index += 1
            cur = ptr.advanced(by: index).pointee
        }
        return bestSamplerate
    }
    
    private func selectChannelLayout(codec: UnsafeMutablePointer<AVCodec>) -> UInt64? {
        guard let ptr: UnsafePointer<UInt64> = codec.pointee.channel_layouts else {
            return nil
        }
        var bestChannelLayout: UInt64 = 0
        var bestChannels: Int32 = 0
        var index: Int = 0
        var cur = ptr.advanced(by: index).pointee
        while cur != 0 {
            let curChannels = av_get_channel_layout_nb_channels(cur)
            if curChannels > bestChannels {
                bestChannelLayout = cur
                bestChannels = curChannels
            }
            index += 1
            cur = ptr.advanced(by: index).pointee
        }
        return bestChannelLayout
    }
    
    //此处的frameSize是根据重采样前的pcm数据计算而来，不需要且不一定等于AVCodecContext中的frameSize
    //原因在于：此函数创建的buffer用于存储重采样后的pcm数据，且后续写入fifo中，而用于编码的数据则从fifo中读取
    private func createSampleBuffer(of codecCtx: UnsafeMutablePointer<AVCodecContext>, frameSize: Int32) -> UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>? {
        
        //申请一个多维数组，维度等于音频的channel数
        let buffer = calloc(Int(codecCtx.pointee.channels), MemoryLayout<UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>>.stride).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        
        //分别给每一个channle对于的缓存分配空间: nb_samples * channles * bitsPreChannel / 8， 其中nb_samples等价于frameSize， bitsPreChannel可由sample_fmt推断得出
        let ret = av_samples_alloc(buffer, nil, codecCtx.pointee.channels, frameSize, codecCtx.pointee.sample_fmt, 0)
        if ret < 0 {
            print("\(#function):\(#line) Could not allocate converted input samples...\(ret)")
            av_freep(buffer)
            free(buffer)
            return nil
        }else {
            return buffer
        }
    }
    
    private func freeSampleBuffer() {
        if self.convertOutSampleBuffer != nil {
            av_freep(self.convertOutSampleBuffer)
            free(self.convertOutSampleBuffer)
            self.convertOutSampleBuffer = nil
        }
    }
    
    private func encodeFIFO(of codecCtx: UnsafeMutablePointer<AVCodecContext>) -> OpaquePointer! {
        return av_audio_fifo_alloc(codecCtx.pointee.sample_fmt, codecCtx.pointee.channels, codecCtx.pointee.frame_size)
    }
    
    private func createConverter(inDesc: FFmpegAudioDescription, outDesc: FFmpegAudioDescription) -> Error? {
        //swr
        if let swrCtx = swr_alloc_set_opts(nil,
                                         av_get_default_channel_layout(outDesc.channels),
                                         outDesc.sampleFormat.toAVSampleFormat(),
                                         outDesc.sampleRate,
                                         av_get_default_channel_layout(inDesc.channels),
                                         inDesc.sampleFormat.toAVSampleFormat(),
                                         inDesc.sampleRate,
                                          0, nil),
            swr_init(swrCtx) == 0 {
            self.swrCtx = swrCtx
            return nil
        }else {
            return NSError.error(self.className, reason: "\(#function):\(#line) Can not init audio swr...")
        }
        
    }
    
}

//MARK: - FIFO
extension FFmpegAudioSession {
    
    func write(buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>!, frameSize: Int32, to fifo: OpaquePointer) -> Error? {
     
        if av_audio_fifo_realloc(fifo, av_audio_fifo_size(fifo) + frameSize) < 0 {
            return NSError.error(self.className, reason: "Could not reallocate FIFO...")
        }
        
        if av_audio_fifo_write(fifo, buffer, frameSize) < frameSize {
            return NSError.error(self.className, reason: "Could not write data to FIFO...")
        }
        
        return nil
    }
    
    func read(from fifo: OpaquePointer, frameSize: Int32, to frame: UnsafeMutablePointer<AVFrame>, flush: Bool = false) -> Int32 {
        
        /*  由于audioCodecContext中的frame_size与src_nb_samples的值很可能是不一样的，
            使用fifo缓存队列进行存储数据，确保了音频数据的连续性，
            当fifo队列中的缓存长度大于等于audioCodecContext的frame_size（可以理解为每次编码的长度）时才进行读取，
            确保每次都能满足audioCodecContext的所需编码长度，从而避免出现杂音等位置情况
         */
        let fifoSize = av_audio_fifo_size(fifo)
        if (flush == false && fifoSize < frameSize) || (flush == true && fifoSize <= 0) {
            return -1
        }
        
        let readFrameSize = min(fifoSize, frameSize)
    
        let frameDataPtr = UnsafeMutablePointer(&frame.pointee.data.0)
        return frameDataPtr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { (ptr) -> Int32 in
            return av_audio_fifo_read(fifo, ptr, readFrameSize)
        }
    
    }
}

//MARK: - Encode
extension FFmpegAudioSession {
    
    func resample(pcm inBuffer: UnsafeMutablePointer<UInt8>, len: Int32, onSuccess: OnResampleFinishedClouser, onFailure: (Error?)->Void) {
        if let swr = self.swrCtx,
            let codecCtx = self.encodecCtx,
            let inDesc = self.inDesc,
            let outDesc = self.config?.desc {
            
            //FIXME: 此处需要根据in buffer的格式进行内存格式转换，当前因为输入输出恰好是Packed类型（LRLRLR），只有data[0]有数据，所以直接指针转换即可
            //如果是Planar格式，则需要对多维数组，维度等于channel数量，然后进行内存重映射，参考函数createSampleBuffer
            var srcBuff = unsafeBitCast(inBuffer, to: UnsafePointer<UInt8>?.self)
            
            //nb_samples: 时间 * 采本率
            //nb_bytes（单位：字节） = (nb_samples * nb_channel * nb_bitsPerChannel) / 8 /*bits per bytes*/
            let src_nb_samples = len/(inDesc.channels * inDesc.bitsPerChannel / 8)
            let dst_nb_samples = Int32(av_rescale_rnd(swr_get_delay(swr, Int64(inDesc.sampleRate)) + Int64(src_nb_samples), Int64(outDesc.sampleRate), Int64(inDesc.sampleRate), AV_ROUND_UP))
        
            if self.resampleDstFrameSize != dst_nb_samples {
                self.freeSampleBuffer()
                if let buffer = self.createSampleBuffer(of: codecCtx, frameSize: Int32(dst_nb_samples)) {
                    self.resampleDstFrameSize = dst_nb_samples
                    self.convertOutSampleBuffer = buffer
                }else {
                    onFailure(NSError.error(self.className, reason: "Failed to creat resample out sample buffer."))
                    return
                }
            }
           
            let nb_samples = swr_convert(swr, self.convertOutSampleBuffer, dst_nb_samples, &srcBuff, src_nb_samples)
            
            if nb_samples > 0 {
                onSuccess(self.convertOutSampleBuffer, nb_samples)
            }else {
                onFailure(NSError.error(self.className, reason: "Failed to resample, ret\(nb_samples)"))
            }
        }
    }
    
    func encode(pcm buffer: UnsafeMutablePointer<UInt8>, len: Int32) {
        
        if let swr = self.swrCtx,
            let codecCtx = self.encodecCtx,
            let encodeInFrame = self.encodeInFrame,
            let fifo = self.encodeFifo,
            let inDesc = self.inDesc,
            let outDesc = self.config?.desc {
            
    //      if av_compare_ts(self.audioNextPts, codecCtx.pointee.time_base, duration, AVRational.init(num: 1, den: 1)) >= 0 {
    //          print("Not need to generate more audio frame")
    //          return
    //      }
            
            var srcBuff = unsafeBitCast(buffer, to: UnsafePointer<UInt8>?.self)
        
            //nb_samples: 时间 * 采本率
            //nb_bytes（单位：字节） = (nb_samples * nb_channel * nb_bitsPerChannel) / 8 /*bits per bytes*/
            let src_nb_samples = len/(inDesc.channels * inDesc.bitsPerChannel / 8)
            let dst_nb_samples = Int32(av_rescale_rnd(swr_get_delay(swr, Int64(inDesc.sampleRate)) + Int64(src_nb_samples), Int64(outDesc.sampleRate), Int64(inDesc.sampleRate), AV_ROUND_UP))
         
            if self.resampleDstFrameSize != dst_nb_samples {
                
                if let buffer = self.createSampleBuffer(of: codecCtx, frameSize: Int32(dst_nb_samples)) {
                    self.resampleDstFrameSize = dst_nb_samples
                    self.convertOutSampleBuffer = buffer
                }else {
                    return
                }
            }
            
            let nb_samples = swr_convert(swr, self.convertOutSampleBuffer, dst_nb_samples, &srcBuff, src_nb_samples)
        
            if nb_samples > 0 {
                
//                if let onResample = self.onAudioResampleFinished {
//                    let size = av_samples_get_buffer_size(nil, codecCtx.pointee.channels, nb_samples, codecCtx.pointee.sample_fmt, 1)
//                    onResample(self.convertOutSampleBuffer!, size)
//                }
                
                if let error = self.convertOutSampleBuffer?.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1, { (buffer)-> Error? in
                    return self.write(buffer: buffer, frameSize: nb_samples, to: fifo)
                }) {
                    print("Can not write audio samples to fifo...\(error.localizedDescription)")
                    return
                }
                
                let readFrameSize = self.read(from: fifo, frameSize: codecCtx.pointee.frame_size, to: encodeInFrame)
                if readFrameSize < 0 {
                    return
                }
                
                self.audioNextPts += Int64(readFrameSize)
                
                self.encode(encodeInFrame, onSuccess: { (buffer, size) in
                    
                }) { (error) in
                    
                }
            }
        }
    }
    
    func encode(_ frame: UnsafeMutablePointer<AVFrame>, onSuccess: (UnsafeMutablePointer<UInt8>?, Int32)->Void, onFailure: (Error?)->Void) {
        
         guard let codecCtx = self.encodecCtx else {
            return
        }
        
        var audioPacket = AVPacket.init()
        av_init_packet(UnsafeMutablePointer<AVPacket>(&audioPacket))
        var muxied = false
        defer {
            if muxied == false {
                av_packet_unref(UnsafeMutablePointer<AVPacket>(&audioPacket))
            }
        }
                  
        //FIXME: How to set pts of audio frame
        frame.pointee.pts = av_rescale_q(self.audioSampleCount, AVRational.init(num: 1, den: codecCtx.pointee.sample_rate), codecCtx.pointee.time_base)
        self.audioSampleCount += Int64(frame.pointee.nb_samples)
     
        var ret = avcodec_send_frame(codecCtx, frame)
        if ret < 0 {
            onFailure(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error about sending a packet for audio encoding."]))
            return
        }
        
        ret = avcodec_receive_packet(codecCtx, UnsafeMutablePointer<AVPacket>(&audioPacket))
        if ret == SWIFT_AV_ERROR_EOF {
            print("avcodec_recieve_packet() encoder flushed...")
        }else if ret == SWIFT_AV_ERROR_EAGAIN {
            print("avcodec_recieve_packet() need more input...")
        }else if ret < 0 {
            onFailure(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding audio."]))
            return
        }
        
        if ret == 0 {

//          print("Encoded audio successfully...")

           let packetSize = Int(audioPacket.size)
            let encodedBytes = unsafeBitCast(malloc(packetSize), to: UnsafeMutablePointer<UInt8>.self)
            memcpy(encodedBytes, audioPacket.data, packetSize)
            onSuccess(encodedBytes, Int32(packetSize))
            
        }
    }
}
