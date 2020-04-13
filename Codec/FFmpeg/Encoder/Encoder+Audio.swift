//
//  Encoder+Audio.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

private let ErrorDomain = "FFmpeg:Audio:Encoder"
//MARK: Encode Audio
extension FFmpegEncoder {
    
    //https://www.jianshu.com/p/e25d56a67c2e
    public func addAudioEncoder(inAudioDesc: AudioDescriptionTuple, outAudioDesc: AudioDescriptionTuple) -> Bool {
        
        var hasError = false
        
        defer {
            if hasError == true {
                self.removeAudioEncoder()
            }
        }
    
        self.inAudioDesc = inAudioDesc
        self.outAudioDesc = outAudioDesc
        
        let codecId: AVCodecID = AV_CODEC_ID_MP2
        if let codec = avcodec_find_encoder(codecId) {
            self.audioCodec = codec
            print("Created audio codec...\(self.selectSampleRate(codec: codec)) - \(self.selectChannelLayout(codec: codec))")
        }else {
            print("Can not create audio codec...")
            hasError = true
            return false
        }
        
        if let context = avcodec_alloc_context3(self.audioCodec) {
            context.pointee.codec_id = codecId
            context.pointee.codec_type = AVMEDIA_TYPE_AUDIO
            context.pointee.sample_fmt = AVSampleFormat(outAudioDesc.sampleFormat) //AV_SAMPLE_FMT_S16
            context.pointee.channel_layout = UInt64(av_get_default_channel_layout(outAudioDesc.channels))//UInt64(AV_CH_LAYOUT_STEREO)
            context.pointee.sample_rate = outAudioDesc.sampleRate//44100
            context.pointee.channels = outAudioDesc.channels//2
            context.pointee.bit_rate = 64000 //128kbps
            context.pointee.time_base.num = 1
            context.pointee.time_base.den = outAudioDesc.sampleRate
            self.audioCodecContext = context
        }else {
            print("Can not create audio codec context...")
            hasError = true
            return false
        }
        
        //看jsmpeg中mp2解码器代码，mp2格式对应的frame_size（nb_samples）似乎是定值：1152
        if avcodec_open2(self.audioCodecContext!, self.audioCodec!, nil) < 0 {
            print("Can not open audio avcodec...")
            hasError = true
            return false
        }
        
        //swr
        if let actx = swr_alloc_set_opts(nil,
                                         av_get_default_channel_layout(outAudioDesc.channels),
                                         AVSampleFormat(outAudioDesc.sampleFormat),
                                         outAudioDesc.sampleRate,
                                         av_get_default_channel_layout(inAudioDesc.channels),
                                         AVSampleFormat(inAudioDesc.sampleFormat),
                                         inAudioDesc.sampleRate,
                                          0, nil),
            swr_init(actx) == 0 {
            self.swrContext = actx
        }else {
            print("Can not init audio swr...")
            hasError = true
            return false
        }
    
        //fifo
        if let fifo = av_audio_fifo_alloc(self.audioCodecContext!.pointee.sample_fmt, self.audioCodecContext!.pointee.channels, 1) {
            self.audioFifo = fifo
        }else {
            print("Can not alloc audio fifo...")
            hasError = true
            return false
        }
        
        return true
    }
    
    public func removeAudioEncoder() {
    
        if let swr = self.swrContext {
            swr_close(swr)
            swr_free(&self.swrContext)
            self.swrContext = nil
        }
        if let context = self.audioCodecContext {
            avcodec_close(context)
            avcodec_free_context(&self.audioCodecContext)
            self.audioCodecContext = nil
        }
        if let fifo = self.audioFifo {
            av_audio_fifo_free(fifo)
            self.audioFifo = nil
        }
        if let frame = self.audioOutFrame {
            av_free(frame)
            self.audioOutFrame = nil
        }
        /*
        if let frameBuffer = self.audioOutFrameBuffer {
            free(frameBuffer)
            self.audioOutFrameBuffer = nil
        }
         */
     
        if let buffer = self.covertedSampleBuffer {
            av_freep(buffer)
            free(buffer)
            self.covertedSampleBuffer = nil
        }

    }

    func selectSampleRate(codec: UnsafeMutablePointer<AVCodec>) -> Int32 {
        //supported_samplerates is a Int32 array contains all the supported samplerate
        guard let ptr: UnsafePointer<Int32> = codec.pointee.supported_samplerates else {
            return 44100
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
    
    func selectChannelLayout(codec: UnsafeMutablePointer<AVCodec>) -> UInt64 {
        guard let ptr: UnsafePointer<UInt64> = codec.pointee.channel_layouts else {
            return UInt64(AV_CH_LAYOUT_STEREO)
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
    
    func initOutputFrame(frameSize: Int32, codecCtx: UnsafeMutablePointer<AVCodecContext>) -> Bool {
    
        guard self.audioOutFrame == nil else {
            return true
        }
   
        if let frame = av_frame_alloc() {
            self.audioOutFrame = frame
            frame.pointee.nb_samples = frameSize
            frame.pointee.channel_layout = codecCtx.pointee.channel_layout
            frame.pointee.format = codecCtx.pointee.sample_fmt.rawValue
            frame.pointee.sample_rate = codecCtx.pointee.sample_rate
            
            if av_frame_get_buffer(frame, 0) < 0 {
                av_frame_free(&self.audioOutFrame)
                return false
            }
        }
        
        return true
    }
    
    func initCovertedSamples(frameSize: Int32) -> Bool {
        
        guard self.audioCodecContext != nil else {
            return false
        }
        
        if self.covertedSampleBuffer != nil {
            av_freep(self.covertedSampleBuffer)
            free(self.covertedSampleBuffer)
            self.covertedSampleBuffer = nil
        }
       
        //申请一个多维数组，维度等于音频的channel数
        self.covertedSampleBuffer = calloc(Int(self.audioCodecContext!.pointee.channels), MemoryLayout<UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>>.stride).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        
        //分别给每一个channle对于的缓存分配空间: nb_samples * channles * bitsPreChannel / 8， 其中nb_samples等价于frameSize， bitsPreChannel可由sample_fmt推断得出
        let ret = av_samples_alloc(self.covertedSampleBuffer, nil, self.audioCodecContext!.pointee.channels, frameSize, self.audioCodecContext!.pointee.sample_fmt, 0)
        
        if ret < 0 {
            print("Could not allocate converted input samples...\(ret)")
            av_freep(self.covertedSampleBuffer)
            free(self.covertedSampleBuffer)
            return false
        }
        return true
    }
    
    /*
    func updateAudioOutFrame(nb_samples: Int32) -> Bool {
        
        guard let outFrame = self.audioOutFrame, let outAudioDesc = self.outAudioDesc else {
            return false
        }
        
        if outFrame.pointee.nb_samples != nb_samples {
            
            var hasError = false
                
            defer {
                if hasError == true {
                  free(self.audioOutFrameBuffer)
                  self.audioOutFrameBuffer = nil
                }
            }
            
            outFrame.pointee.nb_samples = nb_samples
            let size = av_samples_get_buffer_size(nil, outAudioDesc.channels, nb_samples, AVSampleFormat(outAudioDesc.sampleFormat), 1)
            if size < 0 {
                print("Can not get the output sampele buffer size...")
                hasError = true
                return false
            }
            
            self.audioOutFrameBuffer = unsafeBitCast(malloc(Int(size)), to: UnsafeMutablePointer<UInt8>.self)
            
            if avcodec_fill_audio_frame(outFrame, outAudioDesc.channels, AVSampleFormat(outAudioDesc.sampleFormat), self.audioOutFrameBuffer, size, 1) < 0 {
                print("Can not fill output audio frame...")
                hasError = true
                return false
            }
            
            print("The audio output sampele updated..")
        }
    
        return true
    }
 */
    
    func addAudioSamplesToFifo(frameSize: Int32) -> Bool {
        
        guard let fifo = self.audioFifo, self.covertedSampleBuffer != nil  else {
            return false
        }
        
        if av_audio_fifo_realloc(fifo, av_audio_fifo_size(fifo) + frameSize) < 0 {
            print("Could not reallocate FIFO...")
            return false
        }
        
        if av_audio_fifo_write(fifo, unsafeBitCast(self.covertedSampleBuffer, to: UnsafeMutablePointer<UnsafeMutableRawPointer?>.self), frameSize) < frameSize {
            print("Could not write data to FIFO...")
            return false
        }
        
        return true
    }
    
    func readAudioSamplesFromFifoAndEncode(finished: Bool) throws {
        
        guard let codecCtx = self.audioCodecContext,
            let fifo = self.audioFifo else {
            return
        }
        
        /*  由于audioCodecContext中的frame_size与src_nb_samples的值很可能是不一样的，
            使用fifo缓存队列进行存储数据，确保了音频数据的连续性，
            当fifo队列中的缓存长度大于等于audioCodecContext的frame_size（可以理解为每次编码的长度）时才进行读取，
            确保每次都能满足audioCodecContext的所需编码长度，从而避免出现杂音等位置情况
         */
        let fifoSize = av_audio_fifo_size(fifo)
        if (finished == false && fifoSize < codecCtx.pointee.frame_size) || (finished == true && fifoSize > 0) {
            return
        }
        
        let encodeFrameSize = min(fifoSize, codecCtx.pointee.frame_size)
        
        if self.audioOutFrame == nil {
            if self.initOutputFrame(frameSize: encodeFrameSize, codecCtx: self.audioCodecContext!) == false {
                print("Can not create audio output frame...")
                return
            }
        }
        weak var weakSelf = self
        #warning("默认情况下Swift是内存安全的，苹果官方不鼓励直接操作内存。解决方法：使用withUnsafeMutablePointer不仅可以避免手动创建指针变量（可直接操作内存），还限定了指针的作用域，更为安全。")
        try withUnsafeMutablePointer(to: &self.audioOutFrame!.pointee.data.0) { [unowned self] (ptr) in
            #warning("使用withMemoryRebound进行指针类型转换，此处是UnsafeMutablePointer<UInt8> -> UnsafeMutableRawPointer")
            try ptr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { [unowned self] (ptr) in
                if av_audio_fifo_read(fifo, ptr, encodeFrameSize) < encodeFrameSize {
                    throw NSError.error(ErrorDomain, reason: "Could not read data from FIFO.")!
                }
                
                self.audioNextPts += Int64(encodeFrameSize)
                try self.encode(frame: weakSelf!.audioOutFrame!)
            }
        }
       
    }
    
    public func encode(pcmBytes: UnsafeMutablePointer<UInt8>, bytesLen: Int32, displayTime: Double, finished: Bool = false) throws {
                  
//        print("Audio display time: \(displayTime)")
        if self.displayTimeBase == 0 {
            self.displayTimeBase = displayTime
        }
     
        if let swr = self.swrContext,
            let inAudioDesc = self.inAudioDesc,
            let outAudioDesc = self.outAudioDesc {
            
//            if av_compare_ts(self.audioNextPts, codecCtx.pointee.time_base, duration, AVRational.init(num: 1, den: 1)) >= 0 {
//                print("Not need to generate more audio frame")
//                return
//            }
            
            //FIXME: 此处需要根据in buffer的格式进行内存格式转换，当前因为输入输出恰好是Packed类型（LRLRLR），只有data[0]有数据，所以直接指针转换即可
            //如果是Planar格式，则需要对多维数组，维度等于channel数量，然后进行内存重映射，参考函数initCovertedSamples
            var srcBuff = unsafeBitCast(pcmBytes, to: UnsafePointer<UInt8>?.self)
        
            //nb_samples: 时间 * 采本率
            //nb_bytes（单位：字节） = (nb_samples * nb_channel * nb_bitsPerChannel) / 8 /*bits per bytes*/
            let src_nb_samples = bytesLen/(inAudioDesc.channels * inAudioDesc.bitsPerChannel / 8)
            let dst_nb_samples = av_rescale_rnd(swr_get_delay(swr, Int64(inAudioDesc.sampleRate)) + Int64(src_nb_samples), Int64(outAudioDesc.sampleRate), Int64(inAudioDesc.sampleRate), AV_ROUND_UP)
         
            if self.frameSize != Int32(dst_nb_samples) || self.covertedSampleBuffer == nil {
                self.frameSize = Int32(dst_nb_samples)
                if self.initCovertedSamples(frameSize: Int32(dst_nb_samples)) == false {
                    return
                }
            }
            
            let nb_samples = swr_convert(swr, self.covertedSampleBuffer, self.frameSize, &srcBuff, src_nb_samples)
        
            if nb_samples > 0 {
                
                if let onResample = self.onAudioResampleFinished {
                    let size = av_samples_get_buffer_size(nil, self.audioCodecContext!.pointee.channels, nb_samples, self.audioCodecContext!.pointee.sample_fmt, 1)
                    onResample(self.covertedSampleBuffer!, size)
                }
                
                if self.addAudioSamplesToFifo(frameSize: src_nb_samples) == false {
                    print("Can not add audio samples to fifo...")
                    return
                }
                
//                if self.isToWrite() != .audio {
//                    return
//                }
                
//                print("[Audio] encode for now...")
                
                try self.readAudioSamplesFromFifoAndEncode(finished: finished)
    
            }
        }
    }
    
    private
    func encode(frame: UnsafeMutablePointer<AVFrame>) throws {
      
        var audioPacket = AVPacket.init()
        try withUnsafeMutablePointer(to: &audioPacket) { [unowned self] (ptr) in
            try ptr.withMemoryRebound(to: AVPacket.self, capacity: 1) { [unowned self] (ptr) in
                try self.encode(frame: frame, to: ptr)
            }
        }
        
    }
    
    private
    func encode(frame: UnsafeMutablePointer<AVFrame>, to packect: UnsafeMutablePointer<AVPacket>) throws {
        
        guard let codecCtx = self.audioCodecContext else {
            throw NSError.error(ErrorDomain, reason: "Audio Codec Context not initilized yet.")!
        }
        
        av_init_packet(UnsafeMutablePointer<AVPacket>(packect))
      
        //FIXME: How to set pts of audio frame
        self.audioOutFrame!.pointee.pts = av_rescale_q(self.audioSampleCount, AVRational.init(num: 1, den: codecCtx.pointee.sample_rate), codecCtx.pointee.time_base)
        self.audioSampleCount += Int64(self.audioOutFrame!.pointee.nb_samples)
     
        var ret = avcodec_send_frame(codecCtx, self.audioOutFrame)
        if ret < 0 {
            throw NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error about sending a packet for audio encoding."])
        }
        
        ret = avcodec_receive_packet(self.audioCodecContext, UnsafeMutablePointer<AVPacket>(packect))
        if ret == SWIFT_AV_ERROR_EOF {
            print("avcodec_recieve_packet() encoder flushed...")
        }else if ret == SWIFT_AV_ERROR_EAGAIN {
            print("avcodec_recieve_packet() need more input...")
        }else if ret < 0 {
            throw NSError.init(domain: ErrorDomain, code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding audio."])
        }
        
        if ret == 0 {
//          print("Encoded audio successfully...")
            if let onEncoded = self.onAudioEncodeFinished {
                let packetSize = Int(packect.pointee.size)
                let encodedBytes = unsafeBitCast(malloc(packetSize), to: UnsafeMutablePointer<UInt8>.self)
                memcpy(encodedBytes, packect.pointee.data, packetSize)
                onEncoded(encodedBytes, Int32(packetSize))
            }
            
            if self.onMuxerFinished != nil, self.outAudioStream != nil, self.audioCodecContext != nil {

                weak var weakSelf = self
                self.muxingQueue.async {
//                    print("audio \(self.audioNextPts) PTS \(audioPacket.pts) - DTS \(audioPacket.dts)")
                    let bRet = weakSelf!.muxer(packet: packect, stream: weakSelf!.outAudioStream!, timebase: weakSelf!.audioCodecContext!.pointee.time_base)
                    if bRet == false {
                       weakSelf!.onMuxerFaiure?(NSError.error(self.className, code: Int(ret), reason: "Error occured when muxing audio."))
                    }
                    av_packet_unref(packect)
                }
            }else {
                av_packet_unref(UnsafeMutablePointer<AVPacket>(packect))
            }
          
        }
    }
    
}
