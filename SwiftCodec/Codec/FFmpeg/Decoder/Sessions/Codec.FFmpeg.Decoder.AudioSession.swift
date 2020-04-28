//
//  Codec.FFmpeg.Decoder.AudioSession.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/28.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

private let ErrorDomain = "FFmpeg:Audio:Decoder"

extension Codec.FFmpeg.Decoder {
    class AudioSession {
        
        private var config: AudioConfig
        private var decodeQueue: DispatchQueue
        
        private var codecCtx: UnsafeMutablePointer<AVCodecContext>?

        private var decodedFrame: UnsafeMutablePointer<AVFrame>?
        
        private var resampleInBuffer: UnsafeMutablePointer<UnsafePointer<UInt8>?>?
        private var resampleOutBuffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
     
        private var packet: UnsafeMutablePointer<AVPacket>?
        
        private var swrCtx: OpaquePointer?
        
        private var resampleDstFrameSize: Int32 = 0
        
        init(config: AudioConfig, decodeIn queue: DispatchQueue? = nil) throws {
            self.config = config
            self.decodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.VideoSession.decode.queue")
            try self.createCodecContext(config: config)
            try self.createPakcet()
            try self.createDecodedFrame(codecCtx: self.codecCtx!)
            try self.createResampleInBuffer(desc: self.config.srcPCMDesc)
            try self.createResampleOutBuffer(desc: self.config.dstPCMDesc)
            try self.createSwrCtx()
        }
        
        deinit {
            self.destroySwrCtx()
            self.destroyResampleOutBuffer()
            self.destroyResampleInBuffer()
            self.destroyDecodedFrame()
            self.destroyPacket()
            self.destroyCodecCtx()
        }
    }
}

extension Codec.FFmpeg.Decoder.AudioSession {
    
    func createCodecContext(config: Codec.FFmpeg.Decoder.AudioConfig) throws {
        
        let codecId = config.codec.avCodecID
        guard let codec = avcodec_find_decoder(codecId) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio codec.")!
        }
        
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio decode context...")!
        }
        codecCtx.pointee.codec_id = codecId
        codecCtx.pointee.codec_type = AVMEDIA_TYPE_AUDIO
        codecCtx.pointee.channel_layout = codec.pointee.channelLayout ?? UInt64(av_get_default_channel_layout(self.config.srcPCMDesc.channels))
        codecCtx.pointee.sample_rate = self.config.srcPCMDesc.sampleRate
        codecCtx.pointee.channels = self.config.srcPCMDesc.channels
        codecCtx.pointee.time_base.num = 1
        codecCtx.pointee.time_base.den = self.config.srcPCMDesc.sampleRate
        
        guard avcodec_open2(codecCtx, codec, nil) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Can not open audio decode avcodec...")!
        }
        
        self.codecCtx = codecCtx
    }
    
    func destroyCodecCtx() {
        if let ctx = self.codecCtx {
            avcodec_close(ctx)
            avcodec_free_context(&self.codecCtx)
            self.codecCtx = nil
        }
    }
    
}

//MARK: - AVFrame
private
extension Codec.FFmpeg.Decoder.AudioSession {
    
    func createDecodedFrame(codecCtx: UnsafeMutablePointer<AVCodecContext>) throws {
    
        guard let frame = av_frame_alloc() else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio codec in frame...")!
        }
        frame.pointee.nb_samples = codecCtx.pointee.frame_size
        frame.pointee.channel_layout = codecCtx.pointee.channel_layout
        frame.pointee.format = codecCtx.pointee.sample_fmt.rawValue
        frame.pointee.sample_rate = codecCtx.pointee.sample_rate
        
        self.decodedFrame = frame
    }
    
    func destroyDecodedFrame() {
        if let frame = self.decodedFrame {
            av_free(frame)
            self.decodedFrame = nil
        }
    }
}

//MARK: - In SampleBuffer
private
extension Codec.FFmpeg.Decoder.AudioSession {
    
    //此处的frameSize是根据重采样前的pcm数据计算而来，不需要且不一定等于AVCodecContext中的frameSize
    //原因在于：此函数创建的buffer用于存储重采样后的pcm数据，且后续写入fifo中，而用于编码的数据则从fifo中读取
    func createResampleInBuffer(desc: Codec.FFmpeg.Audio.PCMDescription) throws {
        self.resampleInBuffer = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: Int(desc.channels))
    }
    
    func destroyResampleInBuffer() {
        if self.resampleInBuffer != nil {
            self.resampleInBuffer!.deallocate()
            self.resampleInBuffer = nil
        }
    }
    
}

//MARK: - Out SampleBuffer
private
extension Codec.FFmpeg.Decoder.AudioSession {
    
    //此处的frameSize是根据重采样前的pcm数据计算而来，不需要且不一定等于AVCodecContext中的frameSize
    //原因在于：此函数创建的buffer用于存储重采样后的pcm数据，且后续写入fifo中，而用于编码的数据则从fifo中读取
    func createResampleOutBuffer(desc: Codec.FFmpeg.Audio.PCMDescription) throws {
        //申请一个多维数组，维度等于音频的channel数
//        let buffer = calloc(Int(desc.channels), MemoryLayout<UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>>.stride).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        self.resampleOutBuffer = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: Int(desc.channels))
    }
    
    func destroyResampleOutBuffer() {
        if self.resampleOutBuffer != nil {
            av_freep(self.resampleOutBuffer)
            self.resampleOutBuffer!.deallocate()
            self.resampleOutBuffer = nil
        }
    }
    
    func updateResampleOutBuffer(with desc: Codec.FFmpeg.Audio.PCMDescription, nb_samples: Int32) throws {
        
        guard let buffer = self.resampleOutBuffer else {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Resample out buffer not created yet.")!
        }
        //Free last allocated memory
        av_freep(buffer)
        //分别给每一个channle对于的缓存分配空间: nb_samples * channles * bitsPreChannel / 8， 其中nb_samples等价于frameSize， bitsPreChannel可由sample_fmt推断得出
        let ret = av_samples_alloc(buffer, nil, desc.channels, nb_samples, desc.sampleFmt.avSampleFmt, 0)
        if ret < 0 {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Could not allocate converted input samples...\(ret)")!
        }
    }
    
}

//MARK: - AVPacket
private
extension Codec.FFmpeg.Decoder.AudioSession {
    
    func createPakcet() throws {
        guard let packet = av_packet_alloc() else {
            throw NSError.error(ErrorDomain, reason: "Failed to alloc packet.")!
        }
        self.packet = packet
    }
    
    func destroyPacket() {
        if self.packet != nil {
            av_packet_free(&self.packet)
            self.packet = nil
        }
    }
}

//MARK: - Swr Context
private
extension Codec.FFmpeg.Decoder.AudioSession {
    
    func createSwrCtx() throws {
        let inDesc = self.config.srcPCMDesc
        let outDesc = self.config.dstPCMDesc
        //Create swrCtx if neccessary
        if inDesc != outDesc {
            self.swrCtx = try self.createSwrCtx(inDesc: inDesc, outDesc: outDesc)
        }
    }
    
    func destroySwrCtx() {
        if let swr = self.swrCtx {
            swr_close(swr)
            swr_free(&self.swrCtx)
            self.swrCtx = nil
        }
    }
    
    func createSwrCtx(inDesc: Codec.FFmpeg.Audio.PCMDescription, outDesc: Codec.FFmpeg.Audio.PCMDescription) throws -> OpaquePointer? {
        //swr
        if let swrCtx = swr_alloc_set_opts(nil,
                                    av_get_default_channel_layout(outDesc.channels),
                                    outDesc.sampleFmt.avSampleFmt,
                                    outDesc.sampleRate,
                                    av_get_default_channel_layout(inDesc.channels),
                                    inDesc.sampleFmt.avSampleFmt,
                                    inDesc.sampleRate,
                                    0,
                                    nil
            ) {
            let ret = swr_init(swrCtx)
            if ret == 0 {
                return swrCtx
            }else {
                throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Can not init audio swr with returns: \(ret)")!
            }
        }else {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Can not create and alloc audio swr...")!
        }
        
    }
}

extension Codec.FFmpeg.Decoder.AudioSession {
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedDataCallback) {
        
        guard let codecCtx = self.codecCtx,
            let packet = self.packet,
            let decodedFrame = self.decodedFrame else {
                onDecoded(nil, NSError.error(ErrorDomain, reason: "Audio decoder not initialized yet.")!)
                return
        }
        av_init_packet(packet)
        packet.pointee.data = bytes
        packet.pointee.size = size
        
        var ret = avcodec_send_packet(codecCtx, packet)
        
        if ret < 0 {
            onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when sending audio packet for decoding.")!)
            return
        }
        
        ret = avcodec_receive_frame(codecCtx, decodedFrame)
        
        if ret == 0 {
            
            //To resample if necessary
            if self.config.srcPCMDesc != self.config.dstPCMDesc {
                
                
                
            }
            
        }else {
            if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EOF {
                print("[Audio] avcodec_receive_frame() encoder flushed...")
            }else if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EAGAIN {
                print("[Audio] avcodec_receive_frame() need more input...")
            }else if ret < 0 {
                onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when recriving audio frame.")!)
            }
        }
        
        av_frame_unref(decodedFrame)
    }
    
    func resample(frame: UnsafeMutablePointer<AVFrame>) throws {
        
        guard let swr = self.swrCtx,
            let outBuffer = self.resampleOutBuffer,
            let inBuffer = self.resampleInBuffer else {
            throw NSError.error(ErrorDomain, reason: "Swr context not created yet.")!
        }
        
        let inDesc = self.config.srcPCMDesc
        let outDesc = self.config.dstPCMDesc
        
        
        let src_nb_samples = frame.pointee.nb_samples
        
        let dst_nb_samples = Int32(av_rescale_rnd(swr_get_delay(swr, Int64(inDesc.sampleRate)) + Int64(src_nb_samples), Int64(outDesc.sampleRate), Int64(inDesc.sampleRate), AV_ROUND_UP))
        
        if dst_nb_samples > self.resampleDstFrameSize {
            try self.updateResampleOutBuffer(with: outDesc, nb_samples: dst_nb_samples)
            self.resampleDstFrameSize = dst_nb_samples
        }
        
        //TODO: 此处暂时只考虑channel=2的情况，channel>2的情况待优化
        inBuffer[0] = UnsafePointer<UInt8>(frame.pointee.data.0)
        inBuffer[1] = UnsafePointer<UInt8>(frame.pointee.data.1)
        
        let nb_samples = swr_convert(swr, outBuffer, dst_nb_samples, inBuffer, src_nb_samples)
        
        if nb_samples > 0 {
//            return (outBuffer, nb_samples)
        }else {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) => Failed to convert sample buffer.")!
        }
    }
}
