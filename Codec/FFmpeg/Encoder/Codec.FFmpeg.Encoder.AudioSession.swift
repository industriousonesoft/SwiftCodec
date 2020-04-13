//
//  FFmpegEncoderAudioSession.swift
//  FFmpegWrapper
//
//  Created by caowanping on 2020/1/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

private let ErrorDomain = "FFmpeg:Audio:Encoder"

extension Codec.FFmpeg.Encoder {
    //MARK: - FFmpegAudioSession
    class AudioSession: NSObject {
        
        private var inDesc: Codec.FFmpeg.AudioDescription?
        private var config: Codec.FFmpeg.Config?
        
        private var codec: UnsafeMutablePointer<AVCodec>?
        private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
        
        private var audioFifo: OpaquePointer?
        
        private var encodeInFrame: UnsafeMutablePointer<AVFrame>?
        private var convertOutSampleBuffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
        
        private var swrCtx: OpaquePointer?
        
        private var resampleDstFrameSize: Int32 = 0
        private var audioSampleCount: Int64 = 0
        private var audioNextPts: Int64 = 0
        
        private var outDesc = Codec.FFmpeg.Config.defaultDesc
        
        deinit {
            self.close()
        }
        
    }

}

extension Codec.FFmpeg.Encoder.AudioSession {
    
    func open(in desc: Codec.FFmpeg.AudioDescription, config: Codec.FFmpeg.Config) throws {
        
        self.inDesc = desc
        self.config = config
        
        //Codec
        let codecId: AVCodecID = config.codec.toAVCodecID()
        guard let codec = avcodec_find_encoder(codecId) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio codec...")!
        }
        self.codec = codec
        
        //Codec Context
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio codec context...")!
        }
        codecCtx.pointee.codec_id = codecId
        codecCtx.pointee.codec_type = AVMEDIA_TYPE_AUDIO
        codecCtx.pointee.sample_fmt = self.outDesc.sampleFormat.toAVSampleFormat()//AV_SAMPLE_FMT_S16
        codecCtx.pointee.channel_layout = self.selectChannelLayout(codec: codec) ?? UInt64(av_get_default_channel_layout(outDesc.channels))//UInt64(AV_CH_LAYOUT_STEREO)
        codecCtx.pointee.sample_rate = self.selectSampleRate(codec: codec) ?? self.outDesc.sampleRate//44100
        codecCtx.pointee.channels = self.outDesc.channels//2
        codecCtx.pointee.bit_rate = config.bitRate//64000: 128kbps
        codecCtx.pointee.time_base.num = 1
        codecCtx.pointee.time_base.den = self.outDesc.sampleRate
        self.codecCtx = codecCtx
        
        //in frame
        guard let frame = av_frame_alloc() else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio codec in frame...")!
        }
        frame.pointee.nb_samples = codecCtx.pointee.frame_size
        frame.pointee.channel_layout = codecCtx.pointee.channel_layout
        frame.pointee.format = codecCtx.pointee.sample_fmt.rawValue
        frame.pointee.sample_rate = codecCtx.pointee.sample_rate
        
        guard av_frame_get_buffer(frame, 0) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to Allocate new buffer(s) for audio data:")!
        }
        self.encodeInFrame = frame
        
        //看jsmpeg中mp2解码器代码，mp2格式对应的frame_size（nb_samples）似乎是定值：1152
        guard avcodec_open2(codecCtx, codec, nil) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Can not open audio avcodec...")!
        }
        
        //fifo
        guard let fifo = self.createAudioFIFO(of: codecCtx) else {
            throw NSError.error(ErrorDomain, reason: "Can not alloc audio fifo...")!
        }
        self.audioFifo = fifo
        
        //Create swrCtx if neccessary
        if self.inDesc != self.outDesc {
            self.swrCtx = try self.createConverter(inDesc: desc, outDesc: self.outDesc)
        }
    }
    
    func close() {
    
        self.freeSampleBuffer()
        
        if let swr = self.swrCtx {
            swr_close(swr)
            swr_free(&self.swrCtx)
            self.swrCtx = nil
        }

        if let context = self.codecCtx {
            avcodec_close(context)
            avcodec_free_context(&self.codecCtx)
            self.codecCtx = nil
        }
        if let fifo = self.audioFifo {
            av_audio_fifo_free(fifo)
            self.audioFifo = nil
        }
        if let frame = self.encodeInFrame {
            av_free(frame)
            self.encodeInFrame = nil
        }
    
    }
    
}

//MARK: - Initialize Helper
private
extension Codec.FFmpeg.Encoder.AudioSession {
    
    func selectSampleRate(codec: UnsafeMutablePointer<AVCodec>) -> Int32? {
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
    
    func selectChannelLayout(codec: UnsafeMutablePointer<AVCodec>) -> UInt64? {
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
    func createSampleBuffer(desc: Codec.FFmpeg.AudioDescription, frameSize: Int32) throws -> UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?> {
        
        //申请一个多维数组，维度等于音频的channel数
        let buffer = calloc(Int(desc.channels), MemoryLayout<UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>>.stride).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        
        //分别给每一个channle对于的缓存分配空间: nb_samples * channles * bitsPreChannel / 8， 其中nb_samples等价于frameSize， bitsPreChannel可由sample_fmt推断得出
        let ret = av_samples_alloc(buffer, nil, desc.channels, frameSize, desc.sampleFormat.toAVSampleFormat(), 0)
        if ret < 0 {
            av_freep(buffer)
            free(buffer)
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Could not allocate converted input samples...\(ret)")!
        }else {
            return buffer
        }
    }
    
    func freeSampleBuffer() {
        if self.convertOutSampleBuffer != nil {
            av_freep(self.convertOutSampleBuffer)
            free(self.convertOutSampleBuffer)
            self.convertOutSampleBuffer = nil
        }
    }
    
    func createAudioFIFO(of codecCtx: UnsafeMutablePointer<AVCodecContext>) -> OpaquePointer! {
        return av_audio_fifo_alloc(codecCtx.pointee.sample_fmt, codecCtx.pointee.channels, codecCtx.pointee.frame_size)
    }
    
    func createConverter(inDesc: Codec.FFmpeg.AudioDescription, outDesc: Codec.FFmpeg.AudioDescription) throws -> OpaquePointer? {
        //swr
        if let swrCtx = swr_alloc_set_opts(nil,
                                    av_get_default_channel_layout(outDesc.channels),
                                    outDesc.sampleFormat.toAVSampleFormat(),
                                    outDesc.sampleRate,
                                    av_get_default_channel_layout(inDesc.channels),
                                    inDesc.sampleFormat.toAVSampleFormat(),
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

//MARK: - FIFO
private
extension Codec.FFmpeg.Encoder.AudioSession {
    
    func write(buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>!, frameSize: Int32, to fifo: OpaquePointer) -> Error? {
     
        if av_audio_fifo_realloc(fifo, av_audio_fifo_size(fifo) + frameSize) < 0 {
            return NSError.error(ErrorDomain, reason: "Could not reallocate FIFO...")
        }
        
        if av_audio_fifo_write(fifo, buffer, frameSize) < frameSize {
            return NSError.error(ErrorDomain, reason: "Could not write data to FIFO...")
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
        #warning("默认情况下Swift是内存安全的，苹果官方不鼓励直接操作内存。解决方法：使用withUnsafeMutablePointer不仅可以避免手动创建指针变量（可直接操作内存），还限定了指针的作用域，更为安全。")
        return withUnsafeMutablePointer(to: &frame.pointee.data.0) { (ptr) in
            #warning("使用withMemoryRebound进行指针类型转换，此处是UnsafeMutablePointer<UInt8> -> UnsafeMutableRawPointer")
            return ptr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { (ptr) -> Int32 in
                return av_audio_fifo_read(fifo, ptr, readFrameSize)
            }
        }
    
    }
}

//MARK: - Resample
extension Codec.FFmpeg.Encoder.AudioSession {
    
    func resample(pcm inBuffer: UnsafeMutablePointer<UInt8>, len: Int32) throws -> (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, Int32) {
        
        guard let inDesc = self.inDesc else {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) => No in audio description available.")!
        }
        
        //FIXME: 此处需要根据in buffer的格式进行内存格式转换，当前因为输入输出恰好是Packed类型（LRLRLR），只有data[0]有数据，所以直接指针转换即可
        //如果是Planar格式，则需要对多维数组，维度等于channel数量，然后进行内存重映射，参考函数createSampleBuffer
        var srcBuff = unsafeBitCast(inBuffer, to: UnsafePointer<UInt8>?.self)
        
        return try withUnsafeMutablePointer(to: &srcBuff) { [unowned self] (ptr) -> (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, Int32) in
            //nb_samples: 时间 * 采本率
            //nb_bytes（单位：字节） = (nb_samples * nb_channel * nb_bitsPerChannel) / 8 /*bits per bytes*/
            let src_nb_samples = len/(inDesc.channels * inDesc.bitsPerChannel / 8)
            
            if let swr = self.swrCtx {
                
                let dst_nb_samples = Int32(av_rescale_rnd(swr_get_delay(swr, Int64(inDesc.sampleRate)) + Int64(src_nb_samples), Int64(outDesc.sampleRate), Int64(inDesc.sampleRate), AV_ROUND_UP))
            
                if self.resampleDstFrameSize != dst_nb_samples {
                    self.freeSampleBuffer()
                    let buffer = try self.createSampleBuffer(desc: self.outDesc, frameSize: Int32(dst_nb_samples))
                    self.resampleDstFrameSize = dst_nb_samples
                    self.convertOutSampleBuffer = buffer
                }
               
                let nb_samples = swr_convert(swr, self.convertOutSampleBuffer, dst_nb_samples, ptr, src_nb_samples)
                
                if nb_samples > 0 {
                    return (self.convertOutSampleBuffer!, nb_samples)
                }else {
                    throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) => Failed to convert sample buffer.")!
                }
            }else {
                let outSampleBuffer = ptr.withMemoryRebound(to: UnsafeMutablePointer<UInt8>?.self, capacity: 1) { (ptr) -> UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?> in
                    return ptr
                }
                return (outSampleBuffer, src_nb_samples)
            }
        }
        
    }
}

//MARK: - Encode
extension Codec.FFmpeg.Encoder.AudioSession {

    func encode(pcm buffer: UnsafeMutablePointer<UInt8>, len: Int32) throws {
        
        if let codecCtx = self.codecCtx,
            let encodeInFrame = self.encodeInFrame,
            let fifo = self.audioFifo {
        
            let (outSampleBuffer, nb_samples) = try self.resample(pcm: buffer, len: len)
        
            if nb_samples > 0 {

                if let error = outSampleBuffer.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1, { (buffer)-> Error? in
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
                
                self.encode(encodeInFrame, onSuccess: { (packet) in
                    av_packet_unref(packet)
                }) { (error) in
                    
                }
            }
        }
    }
  
    private
    func encode(_ frame: UnsafeMutablePointer<AVFrame>, onSuccess: (UnsafeMutablePointer<AVPacket>)->Void, onFailure: (Error?)->Void) {
        
         guard let codecCtx = self.codecCtx else {
            onFailure(NSError.error(ErrorDomain, reason: "Audio Codec not initilized yet."))
            return
        }
        
        var audioPacket = AVPacket.init()
        withUnsafeMutablePointer(to: &audioPacket) { [unowned self] (ptr) in
            ptr.withMemoryRebound(to: AVPacket.self, capacity: 1) { [unowned self] (ptr) in
                
                av_init_packet(ptr)
                        
                //pts(presentation timestamp): Calculate the time of the sum of sample count for now as the timestmap
                //计算目前为止的采用数所使用的时间作为显示时间戳
                frame.pointee.pts = av_rescale_q(self.audioSampleCount, AVRational.init(num: 1, den: codecCtx.pointee.sample_rate), codecCtx.pointee.time_base)
                self.audioSampleCount += Int64(frame.pointee.nb_samples)
             
                var ret = avcodec_send_frame(codecCtx, frame)
                if ret < 0 {
                    onFailure(NSError.init(domain: ErrorDomain, code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error about sending a packet for audio encoding."]))
                    return
                }
                
                ret = avcodec_receive_packet(codecCtx, ptr)
                if ret == 0 {
                    //print("Encoded audio successfully...")
                    onSuccess(ptr)
                }else {
                    if ret == SWIFT_AV_ERROR_EOF {
                        print("avcodec_recieve_packet() encoder flushed...")
                    }else if ret == SWIFT_AV_ERROR_EAGAIN {
                        print("avcodec_recieve_packet() need more input...")
                    }else if ret < 0 {
                        onFailure(NSError.init(domain: ErrorDomain, code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding audio."]))
                        return
                    }
                    av_packet_unref(ptr)
                }
            }
        }
        
    }
}
