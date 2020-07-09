//
//  FFmpegEncoderAudioSession.swift
//  FFmpegWrapper
//
//  Created by caowanping on 2020/1/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

private let ErrorDomain = "FFmpeg:Audio:Encoder"

extension Codec.FFmpeg.Encoder.Audio {
    //MARK: - FFmpegAudioSession
    class Session {
        
        private var format: Format
     
        private(set) var codecCtx: UnsafeMutablePointer<AVCodecContext>?
        
        private var fifo: OpaquePointer?
        
        private var encodeFrame: UnsafeMutablePointer<AVFrame>?
        
        private var resampleInBuffer: UnsafeMutablePointer<UnsafePointer<UInt8>?>?
        private var resampleOutBuffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
        
        private var swrCtx: OpaquePointer?
        
        private var resampleDstFrameSize: Int32 = 0
        private var sampleCount: Int64 = 0
        
        private var encodeQueue: DispatchQueue
       
        init(format: Format, queue: DispatchQueue? = nil) throws {
            self.format = format
            self.encodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.wangcast.ffmpeg.AudioSession.encode.queue")
            //查看jsmpeg中mp2解码器代码，mp2格式对应的frame_size（nb_samples）似乎是定值：1152
            try self.createCodecCtx(format: format)
            try self.createResampleInBuffer(spec: self.format.srcPCMSpec)
            try self.createResampleOutBuffer(spec: self.format.dstPCMSpec)
            try self.createSwrCtx()
            //使用fifo管道可以确保音频的读写的连续性，每次达到音频格式对应的缓存值时才读取
            try self.createFIFO(codecCtx: self.codecCtx!)
            try self.createEncodeFrame(codecCtx: self.codecCtx!)
        }
        
        deinit {
            self.destroyEncodeFrame()
            self.destroyFIFO()
            self.destroySwrCtx()
            self.destroyResampleOutBuffer()
            self.destroyResampleInBuffer()
            self.destroyCodecCtx()
        }
        
    }

}

extension Codec.FFmpeg.Encoder.Audio.Session {
    
    func createCodecCtx(format: Codec.FFmpeg.Encoder.Audio.Format) throws {
        
        //Codec
        let codecId: AVCodecID = format.codec.avCodecID
        guard let codec = avcodec_find_encoder(codecId) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio codec...")!
        }
      
        //Codec Context
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio encode context...")!
        }
        codecCtx.pointee.codec_id = codecId
        codecCtx.pointee.codec_type = AVMEDIA_TYPE_AUDIO
        codecCtx.pointee.sample_fmt = format.dstPCMSpec.sampleFmt.avSampleFmt
        codecCtx.pointee.channel_layout = codec.pointee.channelLayout ?? UInt64(av_get_default_channel_layout(format.dstPCMSpec.channels))//UInt64(AV_CH_LAYOUT_STEREO)
        codecCtx.pointee.sample_rate = codec.pointee.sampleRate ?? format.dstPCMSpec.sampleRate //44100
        codecCtx.pointee.channels = format.dstPCMSpec.channels //2
        codecCtx.pointee.bit_rate = format.bitRate//64000: 128kbps
        codecCtx.pointee.time_base.num = 1
        codecCtx.pointee.time_base.den = format.dstPCMSpec.sampleRate
     
        //看jsmpeg中mp2解码器代码，mp2格式对应的frame_size（nb_samples）似乎是定值：1152
        guard avcodec_open2(codecCtx, codec, nil) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Can not open audio encode avcodec...")!
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

//MARK: - Encode AVFrame
private
extension Codec.FFmpeg.Encoder.Audio.Session {
    
    func createEncodeFrame(codecCtx: UnsafeMutablePointer<AVCodecContext>) throws {
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
        self.encodeFrame = frame
    }
    
    func destroyEncodeFrame() {
        if let frame = self.encodeFrame {
            av_free(frame)
            self.encodeFrame = nil
        }
    }
}

//MARK: - In SampleBuffer
private
extension Codec.FFmpeg.Encoder.Audio.Session {
    
    //此处的frameSize是根据重采样前的pcm数据计算而来，不需要且不一定等于AVCodecContext中的frameSize
    //原因在于：此函数创建的buffer用于存储重采样后的pcm数据，且后续写入fifo中，而用于编码的数据则从fifo中读取
    func createResampleInBuffer(spec: Codec.FFmpeg.Audio.PCMSpec) throws {
        self.resampleInBuffer = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: Int(spec.channels))
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
extension Codec.FFmpeg.Encoder.Audio.Session {
    
    //此处的frameSize是根据重采样前的pcm数据计算而来，不需要且不一定等于AVCodecContext中的frameSize
    //原因在于：此函数创建的buffer用于存储重采样后的pcm数据，且后续写入fifo中，而用于编码的数据则从fifo中读取
    func createResampleOutBuffer(spec: Codec.FFmpeg.Audio.PCMSpec) throws {
        //申请一个多维数组，维度等于音频的channel数
//        let buffer = calloc(Int(desc.channels), MemoryLayout<UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>>.stride).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        self.resampleOutBuffer = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: Int(spec.channels))
    }
    
    func destroyResampleOutBuffer() {
        if self.resampleOutBuffer != nil {
            av_freep(self.resampleOutBuffer)
            self.resampleOutBuffer!.deallocate()
            self.resampleOutBuffer = nil
        }
    }
    
}

//MARK: - Resample Helper
private
extension Codec.FFmpeg.Encoder.Audio.Session {
    
    func updateSample(buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, with spec: Codec.FFmpeg.Audio.PCMSpec, nb_samples: Int32) throws {
        //Free last allocated memory
        av_freep(buffer)
        //分别给每一个channle对于的缓存分配空间: nb_samples * channles * bitsPreChannel / 8， 其中nb_samples等价于frameSize， bitsPreChannel可由sample_fmt推断得出
        let ret = av_samples_alloc(buffer, nil, spec.channels, nb_samples, spec.sampleFmt.avSampleFmt, 0)
        if ret < 0 {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) Could not allocate converted input samples...\(ret)")!
        }
    }
}

//MARK: - FIFO
private
extension Codec.FFmpeg.Encoder.Audio.Session {
    
    func createFIFO(codecCtx: UnsafeMutablePointer<AVCodecContext>) throws {
   
        if let fifo = av_audio_fifo_alloc(codecCtx.pointee.sample_fmt, codecCtx.pointee.channels, codecCtx.pointee.frame_size) {
            self.fifo = fifo
        }else {
            throw NSError.error(ErrorDomain, reason: "Failed to create audio fifo.")!
        }
    }
    
    func destroyFIFO() {
        if let fifo = self.fifo {
            av_audio_fifo_free(fifo)
            self.fifo = nil
        }
    }
    
}

//MARK: - Swr Context
private
extension Codec.FFmpeg.Encoder.Audio.Session {
    
    func createSwrCtx() throws {
        let inSpec = self.format.srcPCMSpec
        let outSpec = self.format.dstPCMSpec
        //Create swrCtx if neccessary
        if inSpec != outSpec {
            self.swrCtx = try self.createSwrCtx(inSpec: inSpec, outSpec: outSpec)
        }
    }
    
    func destroySwrCtx() {
        if let swr = self.swrCtx {
            swr_close(swr)
            swr_free(&self.swrCtx)
            self.swrCtx = nil
        }
    }
    
    func createSwrCtx(inSpec: Codec.FFmpeg.Audio.PCMSpec, outSpec: Codec.FFmpeg.Audio.PCMSpec) throws -> OpaquePointer? {
        //swr
        if let swrCtx = swr_alloc_set_opts(nil,
                                    av_get_default_channel_layout(outSpec.channels),
                                    outSpec.sampleFmt.avSampleFmt,
                                    outSpec.sampleRate,
                                    av_get_default_channel_layout(inSpec.channels),
                                    inSpec.sampleFmt.avSampleFmt,
                                    inSpec.sampleRate,
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
extension Codec.FFmpeg.Encoder.Audio.Session {
    
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
extension Codec.FFmpeg.Encoder.Audio.Session {
        
    func resample(bytes: UnsafeMutablePointer<UInt8>, size: Int32) throws -> (buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, nb_samples: Int32) {
        
         guard let swr = self.swrCtx,
            let outBuffer = self.resampleOutBuffer,
            let inBuffer = self.resampleInBuffer else {
                throw NSError.error(ErrorDomain, reason: "Swr context not created yet.")!
        }
        
        let inSpec = self.format.srcPCMSpec
        //nb_samples: bytes per channel
        //nb_bytes（单位：字节） = (nb_samples * nb_channel * nb_bitsPerChannel) / 8 /*bits per bytes*/
        let src_nb_samples = size / (inSpec.channels * inSpec.bitsPerChannel / 8)
        
        let outSpec = self.format.dstPCMSpec
            
        let dst_nb_samples = Int32(av_rescale_rnd(swr_get_delay(swr, Int64(inSpec.sampleRate)) + Int64(src_nb_samples), Int64(outSpec.sampleRate), Int64(inSpec.sampleRate), AV_ROUND_UP))
    
        //在写入fifo时可以指定写入的nb_samples，因此此处保留最大的内存分配，避免频繁申请和释放内存
        if dst_nb_samples > self.resampleDstFrameSize {
//            print("resample: \(self.resampleDstFrameSize) - \(dst_nb_samples)")
            try self.updateSample(buffer: outBuffer, with: outSpec, nb_samples: dst_nb_samples)
            self.resampleDstFrameSize = dst_nb_samples
        }
        
        //FIXME: 此处需要根据in buffer的格式进行内存格式转换，当前因为输入输出恰好是Packed类型（LRLRLR），只有data[0]有数据，所以直接指针转换即可
        //如果是Planar格式，则需要对多维数组，维度等于channel数量，然后进行内存重映射，参考函数createSampleBuffer
        //UnsafePointers can be initialized with an UnsafeMutablePointer
        inBuffer[0] = UnsafePointer<UInt8>(bytes)
        inBuffer[1] = nil
    
        let nb_samples = swr_convert(swr, outBuffer, dst_nb_samples, inBuffer, src_nb_samples)
        
        if nb_samples > 0 {
            return (buffer: outBuffer, nb_samples: nb_samples)
        }else {
            throw NSError.error(ErrorDomain, reason: "\(#function):\(#line) => Failed to convert sample buffer.")!
        }
        
    }
}

extension Codec.FFmpeg.Encoder.Audio.Session {
    
    func fill(bytes: UnsafeMutablePointer<UInt8>, size: Int32, onFinished: @escaping (Error?) -> Void) {
        self.encodeQueue.async { [unowned self] in
            if let fifo = self.fifo {
                self.write(bytes: bytes, size: size, to: fifo, onFinished: onFinished)
            }else {
                onFinished(NSError.error(ErrorDomain, reason: "Not for ready to encode yet."))
            }
        }
    }
    
    func readAndEncode(onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedPacketCallback) {
        self.encodeQueue.async { [unowned self] in
            if let fifo = self.fifo {
                self.readAndEncode(from: fifo, onEncoded: onEncoded)
            }else {
                onEncoded(nil, NSError.error(ErrorDomain, reason: "Not for ready to encode yet."))
            }
        }
        
    }
}

//MARK: - Encode
extension Codec.FFmpeg.Encoder.Audio.Session {
 
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedPacketCallback) {
        self.encodeQueue.async { [unowned self] in
            self.innerEncode(bytes: bytes, size: size, onEncoded: onEncoded)
        }
    }

    private
    func innerEncode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedPacketCallback) {
        
        if let fifo = self.fifo {
        
            self.write(bytes: bytes, size: size, to: fifo) { (error) in
                if error != nil {
                    onEncoded(nil, error)
                }else {
                    self.readAndEncode(from: fifo, onEncoded: onEncoded)
                }
            }
            
        }else {
            onEncoded(nil, NSError.error(ErrorDomain, reason: "Not for ready to encode yet.")!)
        }
    }
    
    private
    func write(bytes: UnsafeMutablePointer<UInt8>, size: Int32, to fifo: OpaquePointer, onFinished: (Error?) -> Void) {
        
        do {
            //To write to FIFO after resampled
            let tuple = try self.resample(bytes: bytes, size: size)
            
            if tuple.nb_samples > 0 {

                if let error = tuple.buffer.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1, { (buffer)-> Error? in
                    return self.write(buffer: buffer, frameSize: tuple.nb_samples, to: fifo)
                }) {
                    onFinished(error)
                    return
                }else {
                    onFinished(nil)
                }
            
            }
            
        } catch let err {
            onFinished(err)
        }
    }
    
    private
    func readAndEncode(from fifo: OpaquePointer, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedPacketCallback) {
        
        guard let codecCtx = self.codecCtx, let encodeFrame = self.encodeFrame else {
            onEncoded(nil, NSError.error(ErrorDomain, reason: "Not for ready to encode yet.")!)
            return
        }
        
        let readFrameSize = self.read(from: fifo, frameSize: codecCtx.pointee.frame_size, to: encodeFrame)
          //当前编码对应的缓存区未填充满
          if readFrameSize < 0 {
              return
          }
        
          //pts(presentation timestamp): Calculate the time of the sum of sample count for now as the timestmap
          //计算目前为止的采用数所使用的时间作为显示时间戳
          self.sampleCount += Int64(encodeFrame.pointee.nb_samples)
          let pts = av_rescale_q(self.sampleCount, AVRational.init(num: 1, den: codecCtx.pointee.sample_rate), codecCtx.pointee.time_base)
          encodeFrame.pointee.pts = pts
          
          print("[Audio] encode for now...: \(self.sampleCount) - \(pts)")
          
          self.encode(encodeFrame, with: codecCtx, onFinished: onEncoded)
    }
  
    private
    func encode(_ frame: UnsafeMutablePointer<AVFrame>, with codecCtx: UnsafeMutablePointer<AVCodecContext>, onFinished: @escaping Codec.FFmpeg.Encoder.EncodedPacketCallback) {
        
        var packet = AVPacket.init()
        withUnsafeMutablePointer(to: &packet) { (ptr) in
            
            av_init_packet(ptr)
                
            var ret = avcodec_send_frame(codecCtx, frame)
            if ret < 0 {
                av_packet_unref(ptr)
                onFinished(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when sending frame.")!)
                return
            }
            
            ret = avcodec_receive_packet(codecCtx, ptr)
            
            if ret == 0 {
                //print("Audio: \(frame.pointee.pts) - \(packet.pts) - \(packet.dts)")
                onFinished(ptr, nil)
            }else {
                if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EOF {
                    print("avcodec_recieve_packet() encoder flushed...")
                }else if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EAGAIN {
                    print("avcodec_recieve_packet() need more input...")
                }else if ret < 0 {
                    onFinished(nil, NSError.init(domain: ErrorDomain, code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding audio."]))
                    av_packet_unref(ptr)
                }
            }
        }
        
    }
}
