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
        
        private var srcBuffer: UnsafeMutablePointer<UnsafePointer<UInt8>?>?
        private var dstBuffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
     
        private var packet: UnsafeMutablePointer<AVPacket>?
        
        private var swrCtx: OpaquePointer?
        
        private var srcFrameSize: Int32 = 0
        private var dstFrameSize: Int32 = 0
        private var dstLineSize: Int32 = 0
        
        init(config: AudioConfig, decodeIn queue: DispatchQueue? = nil) throws {
            self.config = config
            self.decodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.VideoSession.decode.queue")
            try self.createCodecContext(config: config)
            try self.createPakcet()
            try self.createDecodedFrame(codecCtx: self.codecCtx!)
            try self.createSrcBuffer(desc: self.config.srcPCMDesc)
            try self.createDstBuffer(desc: self.config.dstPCMDesc)
            try self.createSwrCtx()
        }
        
        deinit {
            self.destroySwrCtx()
            self.destroyDstBuffer()
            self.destroySrcBuffer()
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
        codecCtx.pointee.sample_fmt = self.config.srcPCMDesc.sampleFmt.avSampleFmt
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
    func createSrcBuffer(desc: Codec.FFmpeg.Audio.PCMDescription) throws {
        let count = Int(desc.channels)
        self.srcBuffer = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: count)
        self.srcBuffer?.initialize(repeating: nil, count: count)
    }
    
    func destroySrcBuffer() {
        if self.srcBuffer != nil {
            self.srcBuffer!.deallocate()
            self.srcBuffer = nil
        }
    }
    
}

//MARK: - Out SampleBuffer
private
extension Codec.FFmpeg.Decoder.AudioSession {
    
    //此处的frameSize是根据重采样前的pcm数据计算而来，不需要且不一定等于AVCodecContext中的frameSize
    //原因在于：此函数创建的buffer用于存储重采样后的pcm数据，且后续写入fifo中，而用于编码的数据则从fifo中读取
    func createDstBuffer(desc: Codec.FFmpeg.Audio.PCMDescription) throws {
        //申请一个多维数组，维度等于音频的channel数
//        let buffer = calloc(Int(desc.channels), MemoryLayout<UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>>.stride).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        let count = Int(desc.channels)
        self.dstBuffer = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: count)
        self.dstBuffer?.initialize(repeating: nil, count: count)
    }
    
    func destroyDstBuffer() {
        if self.dstBuffer != nil {
            av_freep(self.dstBuffer)
            self.dstBuffer!.deallocate()
            self.dstBuffer = nil
        }
    }
    
    func updateDstBuffer(with desc: Codec.FFmpeg.Audio.PCMDescription, nb_samples: Int32) throws -> Int32 {
        
        guard let buffer = self.dstBuffer else {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Resample out buffer not created yet.")!
        }
        //Free last allocated memory
        av_freep(buffer)
        var linesize: Int32 = 0
        //Way-01
//        let buffer_size = av_samples_get_buffer_size(&linesize, desc.channels ,nb_samples, desc.sampleFmt.avSampleFmt, 1)
//        let out_buffer = av_malloc(Int(buffer_size))
        //Get buffer_size
        //Way-02
        //linesize = nb_samples * bitsPerChannel / 8
        //当采样格式是packed（LRLRLR...）时，buffer_size = linesize，是planar(LLL..RRR..)时，buffer_size = linesize * channels
        let ret = av_samples_alloc(buffer, &linesize, desc.channels, nb_samples, desc.sampleFmt.avSampleFmt, 1)
        if ret < 0 {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Could not allocate converted input samples...\(ret)")!
        }
//        print("\(#function) => linesize: \(linesize) -> \(ret)")

        return linesize
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
        self.swrCtx = try self.createSwrCtx(inDesc: self.config.srcPCMDesc, outDesc: self.config.dstPCMDesc)
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

//MARK: - Decode
extension Codec.FFmpeg.Decoder.AudioSession {
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedAudioCallback) {
        
        guard let codecCtx = self.codecCtx,
            let packet = self.packet,
            let decodedFrame = self.decodedFrame else {
                onDecoded(nil, NSError.error(ErrorDomain, reason: "Audio decoder not initialized yet.")!)
                return
        }
        
        av_init_packet(packet)
        packet.pointee.data = bytes
        packet.pointee.size = size
        packet.pointee.pos = 0
        packet.pointee.pts = Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE
        packet.pointee.dts = Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE
        
        var ret = avcodec_send_packet(codecCtx, packet)
        
        if ret < 0 {
            onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when sending audio packet for decoding.")!)
            return
        }
        
        ret = avcodec_receive_frame(codecCtx, decodedFrame)
        
        if ret == 0 {
            
            do {
                let tuple = try self.resample(frame: decodedFrame)
//                let dataList = self.dump(from: tuple.buffer, size: tuple.size)
//                onDecoded(dataList, nil)
                let bytes = self.dumpBytes(from: tuple.buffer, size: tuple.size)
                onDecoded(bytes, nil)
            } catch let err {
                onDecoded(nil, err)
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
    
    func resample(frame: UnsafeMutablePointer<AVFrame>) throws -> (buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, size: Int32) {
        
        guard let swr = self.swrCtx,
            let dstBuffer = self.dstBuffer,
            let srcBuffer = self.srcBuffer else {
            throw NSError.error(ErrorDomain, reason: "Swr context not created yet.")!
        }
        
        let inDesc = self.config.srcPCMDesc
        let outDesc = self.config.dstPCMDesc
        
        let src_nb_samples = frame.pointee.nb_samples
        
        if src_nb_samples > self.srcFrameSize {
            //Calculate the destination nb_samples according to the source nb_samples
            let dst_nb_samples = Int32(av_rescale_rnd(swr_get_delay(swr, Int64(inDesc.sampleRate)) + Int64(src_nb_samples), Int64(outDesc.sampleRate), Int64(inDesc.sampleRate), AV_ROUND_UP))
            let lineSize = try self.updateDstBuffer(with: outDesc, nb_samples: dst_nb_samples)
            self.srcFrameSize = src_nb_samples
            self.dstFrameSize = dst_nb_samples
            self.dstLineSize = lineSize
//            print("Audio Decoded LineSize: \(src_nb_samples) - \(dst_nb_samples) - \(lineSize)")
        }
        
//        print("Audio Decoded Data: \(String(describing: frame.pointee.data.0)) - \(String(describing: frame.pointee.data.1))")
      
        //TODO: 此处暂时只考虑channel=2的情况，channel>2的情况待优化
        srcBuffer[0] = UnsafePointer<UInt8>(frame.pointee.data.0)
        srcBuffer[1] = UnsafePointer<UInt8>(frame.pointee.data.1)
 
        let nb_samples = swr_convert(swr, dstBuffer, self.dstFrameSize, srcBuffer, src_nb_samples)
        
        if nb_samples > 0 {
//            print("nb_samples: \(nb_samples)")
            return (buffer: dstBuffer, size: self.dstLineSize)
        }else {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) => Failed to convert sample buffer.")!
        }
    }
}



//MARK: - Dump
extension Codec.FFmpeg.Decoder.AudioSession {
    
    func dump(from frame: UnsafeMutablePointer<AVFrame>) -> [Data] {
        var dataList = Array<Data>.init()
        if let bytes = frame.pointee.data.0 {
            let size = frame.pointee.linesize.0
            let data = Data.init(bytes:bytes, count: Int(size))
            dataList.append(data)
        }
        return dataList
    }

    func dumpData(from buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, size: Int32) -> [Data] {
        var dataList = Array<Data>.init()
        if buffer[0] != nil {
            let data = Data.init(bytes: buffer[0]!, count: Int(size))
            dataList.append(data)
        }
        
        if buffer[1] != nil {
            let data = Data.init(bytes: buffer[1]!, count: Int(size))
            print("channel-1: \(data)")
            dataList.append(data)
        }
        return dataList
    }
    
    func dumpBytes(from buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, size: Int32) -> (bytes: UnsafeMutablePointer<UInt8>, size: Int)? {
        if buffer[0] != nil {
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(size))
            bytes.assign(from: buffer[0]!, count: Int(size))
            return (bytes: bytes, size: Int(size))
        }
        return nil
    }
}
