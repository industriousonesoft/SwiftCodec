//
//  Encoder.swift
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

import Foundation
import CFFmpeg
import FFmepgWrapperOCBridge

//MARK: Public
public typealias OnResampleFinishedClouser = (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, Int32) -> Void
public typealias OnEncodeFinishedClouser = (UnsafeMutablePointer<UInt8>, Int32) -> Void
public typealias OnMuxerFinishedClouser = (UnsafeMutablePointer<UInt8>, Int32) -> Void
public typealias OnFailuerClouser = (NSError?)->Void

public let SWIFT_AV_SAMPLE_FMT_S16: Int32 = AV_SAMPLE_FMT_S16.rawValue
public let SWIFT_AV_SAMPLE_FMT_S16P: Int32 = AV_SAMPLE_FMT_S16P.rawValue
public let SWIFT_AV_SAMPLE_FMT_FLT: Int32 = AV_SAMPLE_FMT_FLT.rawValue
public let SWIFT_AV_SAMPLE_FMT_FLTP: Int32 = AV_SAMPLE_FMT_FLTP.rawValue

public enum EncoderType {
    case audio
    case video
    case both
}

//MARK: Private
let SWIFT_AV_PIX_FMT_RGB32 = AVPixelFormat(FFmepgWrapperOCBridge.avPixelFormatRGB32())
let SWIFT_AV_ERROR_EOF = FFmepgWrapperOCBridge.avErrorEOF()
let SWIFT_AV_ERROR_EAGAIN = FFmepgWrapperOCBridge.avErrorEagain()
let SWIFT_AC_NOPTS_VALUE = FFmepgWrapperOCBridge.avNoPTSValue()

private let Video_Timebase = AVRational.init(num: 1, den: 90000)

private let VideoEncodeDomain: String = "VideoEncoder"
private let AudioEncodeDomain: String = "AudioEncoder"
private let MuxerEncodeDomain: String = "MuxerEncoder"

private enum AudioOrVideoToWriteType {
    case none
    case audio
    case video
}

//MARK: - FFmpegEncoder
public typealias AudioDescriptionTuple = (sampleRate: Int32, channels: Int32, bitsPerChannel: Int32, sampleFormat: Int32)

public class FFmpegEncoder: NSObject {
    
    public private(set) var inSize: CGSize = .zero
    public private(set) var outSize: CGSize = .zero
    
    public private(set) var encodeVideo: Bool = true
    public private(set) var encodeAudio: Bool = true
    
    private var displayTimeBase: Double = 0
    private var isWroteHeader: Bool = false

    //Muxer
    private lazy var muxingQueue: DispatchQueue = {
        DispatchQueue.init(label: "com.zdnet.encoder.muxingQueue")
    }()
    private var outFMTCtx: UnsafeMutablePointer<AVFormatContext>?
    
    //Video
    private var videoCodec: UnsafeMutablePointer<AVCodec>?
    private var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    
    private var videoInFrame: UnsafeMutablePointer<AVFrame>?
    private var videoOutFrame: UnsafeMutablePointer<AVFrame>?
  
    private var swsContext: OpaquePointer?

    private var outVideoStream: UnsafeMutablePointer<AVStream>?
    private var videoNextPts: Int64 = 0
    
    //Audio
    private var audioCodec: UnsafeMutablePointer<AVCodec>?
    private var audioCodecContext: UnsafeMutablePointer<AVCodecContext>?

    private var audioOutFrame: UnsafeMutablePointer<AVFrame>?

    private var covertedSampleBuffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
    private var audioFifo: OpaquePointer?
    
    private var swrContext: OpaquePointer?
    
    private var outAudioStream: UnsafeMutablePointer<AVStream>?
    
    //General
    private var inAudioDesc: AudioDescriptionTuple?
    private var outAudioDesc: AudioDescriptionTuple?
    
    private var audioSampleCount: Int64 = 0
    private var audioNextPts: Int64 = 0
    private var frameSize: Int32 = 0
    private(set) var encoderType: EncoderType!
    
    //Callback
    public var onVideoEncodeFinished: OnEncodeFinishedClouser?
    public var onVideoEncoderFaiure: OnFailuerClouser?
    
    public var onAudioEncodeFinished: OnEncodeFinishedClouser?
    public var onAudioResampleFinished: OnResampleFinishedClouser?
    public var onAudioEncoderFaiure: OnFailuerClouser?
    
    public var onMuxerFinished: OnMuxerFinishedClouser?
    public var onMuxerFaiure: OnFailuerClouser?
    
    private var videoSrcSliceArray: [UnsafePointer<UInt8>?]? {
        get {
            if let frame = self.videoInFrame {
                return [
                    UnsafePointer<UInt8>(frame.pointee.data.0),
                    UnsafePointer<UInt8>(frame.pointee.data.1),
                    UnsafePointer<UInt8>(frame.pointee.data.2),
                    UnsafePointer<UInt8>(frame.pointee.data.3),
                    UnsafePointer<UInt8>(frame.pointee.data.4),
                    UnsafePointer<UInt8>(frame.pointee.data.5),
                    UnsafePointer<UInt8>(frame.pointee.data.6),
                    UnsafePointer<UInt8>(frame.pointee.data.7),
                ]
            }else {
                return nil
            }
        }
    }
    private var videoSrcStrideArray: [Int32]? {
        get {
            if let frame = self.videoInFrame {
                return [
                    frame.pointee.linesize.0,
                    frame.pointee.linesize.1,
                    frame.pointee.linesize.2,
                    frame.pointee.linesize.3,
                    frame.pointee.linesize.4,
                    frame.pointee.linesize.5,
                    frame.pointee.linesize.6,
                    frame.pointee.linesize.7
                ]
            }else {
                return nil
            }
        }
    }
                  
    private var videoDstSliceArray: [UnsafeMutablePointer<UInt8>?]? {
        get {
            if let frame = self.videoOutFrame {
                return [
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.0),
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.1),
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.2),
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.3),
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.4),
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.5),
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.6),
                    UnsafeMutablePointer<UInt8>(frame.pointee.data.7),
                ]
            }else {
                return nil
            }
        }
    }
    private var videoDstStrideArray: [Int32]? {
        get {
            if let frame = self.videoOutFrame {
                return [
                    frame.pointee.linesize.0,
                    frame.pointee.linesize.1,
                    frame.pointee.linesize.2,
                    frame.pointee.linesize.3,
                    frame.pointee.linesize.4,
                    frame.pointee.linesize.5,
                    frame.pointee.linesize.6,
                    frame.pointee.linesize.7
                ]
            }else {
                return nil
            }
        }
    }
                  
    public init(_ type: EncoderType) {
        self.encoderType = type
        super.init()
    }
    
    deinit {
    }
    
    public func start() {
        self.addStream()
    }
    
    public func stop() {
        self.removeAudioEncoder()
        self.removeVideoEncoder()
        self.destoryMuxer()
    }
    
}

//MARK: Encode Video
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
    
    func readAudioSamplesFromFifoAndEncode(finished: Bool) {
        
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
        let frameDataPtr = UnsafeMutablePointer(&self.audioOutFrame!.pointee.data.0)
        frameDataPtr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { ptr in
            
            if av_audio_fifo_read(fifo, ptr, encodeFrameSize) < encodeFrameSize {
               print("Could not read data from FIFO...")
               return
            }
            
            weakSelf?.audioNextPts += Int64(encodeFrameSize)
            
            weakSelf?.encode(audio: weakSelf!.audioOutFrame!)
        }
        
    }
    
    public func encode(pcmBytes: UnsafeMutablePointer<UInt8>, bytesLen: Int32, displayTime: Double, finished: Bool = false) {
                  
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
                
                self.readAudioSamplesFromFifoAndEncode(finished: finished)
    
            }
        }
    }
    
    func encode(audio frame: UnsafeMutablePointer<AVFrame>) {
      
        guard let codecCtx = self.audioCodecContext else {
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
        self.audioOutFrame!.pointee.pts = av_rescale_q(self.audioSampleCount, AVRational.init(num: 1, den: codecCtx.pointee.sample_rate), codecCtx.pointee.time_base)
        self.audioSampleCount += Int64(self.audioOutFrame!.pointee.nb_samples)
     
        var ret = avcodec_send_frame(codecCtx, self.audioOutFrame)
        if ret < 0 {
            self.onAudioEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error about sending a packet for audio encoding."]))
            return
        }
        
        ret = avcodec_receive_packet(self.audioCodecContext, UnsafeMutablePointer<AVPacket>(&audioPacket))
        if ret == SWIFT_AV_ERROR_EOF {
            print("avcodec_recieve_packet() encoder flushed...")
        }else if ret == SWIFT_AV_ERROR_EAGAIN {
            print("avcodec_recieve_packet() need more input...")
        }else if ret < 0 {
            self.onAudioEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding audio."]))
            return
        }
        
        if ret == 0 {

//          print("Encoded audio successfully...")

            if let onEncoded = self.onAudioEncodeFinished {
                let packetSize = Int(audioPacket.size)
                let encodedBytes = unsafeBitCast(malloc(packetSize), to: UnsafeMutablePointer<UInt8>.self)
                memcpy(encodedBytes, audioPacket.data, packetSize)
                onEncoded(encodedBytes, Int32(packetSize))
            }
            
            if self.onMuxerFinished != nil, self.outAudioStream != nil, self.audioCodecContext != nil {
                muxied = true
                weak var weakSelf = self
                self.muxingQueue.async {
//                    print("audio \(self.audioNextPts) PTS \(audioPacket.pts) - DTS \(audioPacket.dts)")
                    let bRet = weakSelf!.muxer(packet: &audioPacket, stream: weakSelf!.outAudioStream!, timebase: weakSelf!.audioCodecContext!.pointee.time_base)
                    if bRet == false {
                       weakSelf!.onMuxerFaiure?(NSError.error(self.className, code: Int(ret), reason: "Error occured when muxing audio."))
                    }
                    av_packet_unref(UnsafeMutablePointer<AVPacket>(&audioPacket))
                }
            }
          
        }
    }
    
}

//MARK: Encode Video
extension FFmpegEncoder {
    
    public func addVideoEncoder(outSize: CGSize, bitrate: Int64, fps: Int32, gopSize: Int32, dropBFrame: Bool) throws {
            
        self.outSize = outSize
        
        //Deprecated, No neccessary any more!
//        avcodec_register_all()
        let codecId: AVCodecID = AV_CODEC_ID_MPEG1VIDEO
        if let codec = avcodec_find_encoder(codecId) {
            self.videoCodec = codec
        }else {
            throw NSError.error(VideoEncodeDomain, reason: "Failed to create video codec.")!
        }
        
        if let context = avcodec_alloc_context3(self.videoCodec) {
            context.pointee.codec_id = codecId
            context.pointee.codec_type = AVMEDIA_TYPE_VIDEO
            context.pointee.dct_algo = FF_DCT_FASTINT
            context.pointee.bit_rate = bitrate
            context.pointee.width = Int32(outSize.width)
            context.pointee.height = Int32(outSize.height)
            context.pointee.time_base.num = 1
            //All the fps supported by mpeg1: 0, 23.976, 24, 25, 29.97, 30, 50, 59.94, 60
            context.pointee.time_base.den = fps
            context.pointee.gop_size = gopSize // 2s: 2 * 25
            //Drop out B frame
            if dropBFrame {
                context.pointee.max_b_frames = 0
            }
            context.pointee.pix_fmt = AV_PIX_FMT_YUV420P
            context.pointee.mb_cmp = FF_MB_DECISION_RD
            //CBR is default setting, VBR Setting blow:
//            context.pointee.flags |= AV_CODEC_FLAG_QSCALE
//            context.pointee.rc_max_rate =
//            context.pointee.rc_min_rate =
            self.videoCodecContext = context
        }else {
            throw NSError.error(VideoEncodeDomain, reason: "Failed to create video codec context.")!
        }
        
        if avcodec_open2(self.videoCodecContext!, self.videoCodec!, nil) < 0 {
            throw NSError.error(VideoEncodeDomain, reason: "Failed to open video avcodec.")!
        }
        
        try self.createVideoOutFrame(size: self.outSize)
    
    }
    
    func removeVideoEncoder() {
        
        if let context = self.videoCodecContext {
            avcodec_close(context)
            avcodec_free_context(&self.videoCodecContext)
            self.videoCodecContext = nil
        }
        
        self.destorySwsContext()
        self.destoryVideoOutFrame()
        self.destoryVideoInFrame()
    }
    
    //MARK: - Video Encode Context
    
    //MARK: - Out Video Frame
    private func destoryVideoOutFrame() {
        if let frame = self.videoOutFrame {
            av_free(frame)
            self.videoOutFrame = nil
        }
    }
    
    private func createVideoOutFrame(size: CGSize) throws {
        if let frame = av_frame_alloc() {
            frame.pointee.format = AV_PIX_FMT_YUV420P.rawValue
            frame.pointee.width = Int32(size.width)
            frame.pointee.height = Int32(size.height)
            frame.pointee.pts = 0
            
            let frameSize = av_image_get_buffer_size(AV_PIX_FMT_YUV420P,  Int32(size.width), Int32(size.height), 1)
            if frameSize < 0 {
                throw NSError.error(VideoEncodeDomain, reason: "Can not get the video output frame buffer size.")!
            }
            
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(frameSize))
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), buffer, AV_PIX_FMT_YUV420P, Int32(size.width), Int32(size.height), 1) < 0 {
                throw NSError.error(VideoEncodeDomain, reason: "Can not get the video output frame buffer size.")!
            }
            
            self.videoOutFrame = frame
            
        }else {
            throw NSError.error(VideoEncodeDomain, reason: "Can not get the video output frame buffer size.")!
        }
    }
    
    //MARK: - Input Video Frame
    private func destoryVideoInFrame() {
        if let frame = self.videoInFrame {
            av_free(frame)
            self.videoInFrame = nil
        }
    }
    
    private func createVideoInFrame(size: CGSize) throws {
        //InFrame
        if let frame = av_frame_alloc() {
            frame.pointee.format = SWIFT_AV_PIX_FMT_RGB32.rawValue
            frame.pointee.width = Int32(size.width)
            frame.pointee.height = Int32(size.height)
            frame.pointee.pts = 0
            
            let frameSize = av_image_get_buffer_size(SWIFT_AV_PIX_FMT_RGB32, Int32(size.width), Int32(size.height), 1)
            if frameSize < 0 {
                throw NSError.error(VideoEncodeDomain, reason: "Can not get the video input frame buffer size.")!
            }
            
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(frameSize))
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), buffer, SWIFT_AV_PIX_FMT_RGB32, Int32(size.width), Int32(size.height), 1) < 0 {
                throw NSError.error(VideoEncodeDomain, reason: "Can not fill the video input frame buffer.")!
            }
            
            self.videoInFrame = frame
            
        }else {
            throw NSError.error(VideoEncodeDomain, reason: "Can not alloc the video input frame.")!
        }
    }
    
    //MARK: - Sws Context
    private func destorySwsContext() {
        if let sws = self.swsContext {
            sws_freeContext(sws)
            self.swsContext = nil
        }
    }
    
    private func createSwsContect(inSize: CGSize, outSize: CGSize) throws {
        if let sws = sws_getContext(Int32(inSize.width), Int32(inSize.height), SWIFT_AV_PIX_FMT_RGB32, Int32(outSize.width), Int32(outSize.height), AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, nil, nil, nil) {
            self.swsContext = sws
        }else {
            throw NSError.error(VideoEncodeDomain, reason: "Can not create sws context.")!
        }
    }
     
    //MARK: - Video Encode
    public func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double) {
        
//        let inDataArray = unsafeBitCast([rgbPixels], to: UnsafePointer<UnsafePointer<UInt8>?>?.self)
//        let inLineSizeArray = unsafeBitCast([self.inWidth * 4], to: UnsafePointer<Int32>.self)
//        print("Video display time: \(displayTime)")
        
        if __CGSizeEqualToSize(self.inSize, size) == false {
            do {
                self.destoryVideoInFrame()
                self.destorySwsContext()
                try self.createVideoInFrame(size: size)
                try self.createSwsContect(inSize: size, outSize: self.outSize)
                self.inSize = size
            } catch let err {
                self.onVideoEncoderFaiure?(NSError.error(VideoEncodeDomain, reason: err.localizedDescription))
                return
            }
        }
        
        if self.encoderType == .video && self.displayTimeBase == 0 {
            self.displayTimeBase = displayTime
        }
      
        if self.isToWrite() == .none {
            print("[None] Nothing to encode for now...")
            return
        }
        
        if self.videoOutFrame != nil && self.videoInFrame != nil {
            
            self.videoInFrame!.pointee.data.0 = bytes
            //输入使用的是AV_PIX_FMT_RGB32: width x 4(RGBA有4个颜色通道个数) = bytesPerRow = stride
            self.videoInFrame!.pointee.linesize.0 = Int32(size.width) * 4
           
            //TODO: Using libyuv to convert RGB32 to YUV420 is faster then sws_scale
            //Return the height of the output slice
            //不同于音频重采样，视频格式转换不影响视频采样率，所以转换前后的同一时间内采样数量不变
            let destSliceH = sws_scale(self.swsContext, self.videoSrcSliceArray, self.videoSrcStrideArray, 0, Int32(size.height), self.videoDstSliceArray, self.videoDstStrideArray)
            
            if destSliceH > 0 {
                
                let duration = displayTime - self.displayTimeBase
                let nb_samples_count = Int64(duration * Double(Video_Timebase.den))
                
                //这一步很关键！在未知输入视频的帧率或者帧率是一个动态值时，使用视频采样率（一般都是90K）作为视频量增幅的参考标准
                //然后，将基于采样频率的增量计数方式转换为基于当前编码帧率的增量计数方式
                self.videoOutFrame!.pointee.pts = av_rescale_q(nb_samples_count, Video_Timebase, self.videoCodecContext!.pointee.time_base)
                self.videoNextPts = self.videoOutFrame!.pointee.pts
                
                if self.isToWrite() == .audio {
                    //print("[Video] not to encode for now...")
                    return
                }
                
//                print("[Video] encode for now...")
                var videoPacket = AVPacket.init()
                av_init_packet(UnsafeMutablePointer<AVPacket>(&videoPacket))
                var muxied = false
                defer {
                    if muxied == false {
                        av_packet_unref(UnsafeMutablePointer<AVPacket>(&videoPacket))
                    }
                }
               
                var ret = avcodec_send_frame(self.videoCodecContext, self.videoOutFrame)
                if ret < 0 {
                    self.onVideoEncoderFaiure?(NSError.error(VideoEncodeDomain, code: Int(ret), reason: "Error about sending a packet for video encoding.")!)
                    return
                }
                
                ret = avcodec_receive_packet(self.videoCodecContext, UnsafeMutablePointer<AVPacket>(&videoPacket))
                if ret == SWIFT_AV_ERROR_EOF {
                    print("avcodec_recieve_packet() encoder flushed...")
                }else if ret == SWIFT_AV_ERROR_EAGAIN {
                    print("avcodec_recieve_packet() need more input...")
                }else if ret < 0 {
                    self.onVideoEncoderFaiure?(NSError.error(VideoEncodeDomain, code: Int(ret), reason: "Error occured when encoding video.")!)
                    return
                }
                
                if ret == 0 {

                    //TODO: 此处存在一个疑问：//视频编码如果不存在B帧，那么packet中pts与dts是一致的。但是编码得到的packet中pts与dts以及编码前frame的pts的值均不相同，
//                    print("Video packet pts: \(videoPacket.pts) - dts: \(videoPacket.dts)")
                    
                    if self.videoOutFrame!.pointee.key_frame == 1 {
                        videoPacket.flags |= AV_PKT_FLAG_KEY
                    }
                  
                    if let onEncoded = self.onVideoEncodeFinished {
                        let packetSize = Int(videoPacket.size)
                        let encodedBytes = unsafeBitCast(malloc(packetSize), to: UnsafeMutablePointer<UInt8>.self)
                        memcpy(encodedBytes, videoPacket.data, packetSize)
                        onEncoded(encodedBytes, Int32(packetSize))
                    }
                   
                    //B相对于I帧和P帧而言是压缩率最高的，更好的保证视频质量，但是由于需要向后一帧参考，所以不适合用于实时性要求高的场合。
                    //当前编码用于镜像，实时性优先，所以去掉了B帧
                    if self.onMuxerFinished != nil, self.outVideoStream != nil, self.videoCodecContext != nil {
                        muxied = true
                        weak var weakSelf = self
                        self.muxingQueue.async {
                            let bRet = weakSelf!.muxer(packet: &videoPacket, stream: weakSelf!.outVideoStream!, timebase: weakSelf!.videoCodecContext!.pointee.time_base)
                            if bRet == false {
                                weakSelf!.onMuxerFaiure?(NSError.error(VideoEncodeDomain, code: Int(ret), reason: "Error occured when muxing video.")!)
                            }
                            av_packet_unref(UnsafeMutablePointer<AVPacket>(&videoPacket))
                        }
                        
                    }
                }
            }
           
        }else {
            self.onVideoEncoderFaiure?(NSError.error(VideoEncodeDomain, reason: "Encoder not initailized.")!)
        }
        
    }
}

//MARK: Muxer
extension FFmpegEncoder {
    
    func writeTSHeader() {
        guard let fmtCtx = self.outFMTCtx else {
            return
        }
        weak var weakSelf = self
        self.muxingQueue.async {
            if avformat_write_header(fmtCtx, nil) < 0 {
                print("Error occurred when writing header.")
            }else {
                weakSelf?.isWroteHeader = true
            }
        }
        
    }
    
    func writeTSTrailer() {
        guard let fmtCtx = self.outFMTCtx else {
            return
        }
        weak var weakSelf = self
        self.muxingQueue.async {
            if av_write_trailer(fmtCtx) != 0 {
                print("Error occurred when writing trailer.")
            }else {
                weakSelf?.isWroteHeader = false
            }
        }
    }
    
    func addStream() {
        
        if self.outFMTCtx == nil {
            let ioBufferSize: Int = 512*1024 //32768
            let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: ioBufferSize)
            let writable: Int = 1
            let ioCtx = avio_alloc_context(buff, Int32(ioBufferSize), Int32(writable), unsafeBitCast(self, to: UnsafeMutableRawPointer.self), nil, muxerCallback, nil)
            
            if avformat_alloc_output_context2(&outFMTCtx, nil, "mpegts", nil) < 0 {
                print("Could not create output context.")
                return
            }
            
            self.outFMTCtx?.pointee.pb = ioCtx
            self.outFMTCtx?.pointee.flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_NOFILE | AVFMT_FLAG_FLUSH_PACKETS
        }
        
        if let fmtCtx = self.outFMTCtx {
            
            if let codec = self.videoCodec, let codecCtx = self.videoCodecContext {
                self.outVideoStream = avformat_new_stream(fmtCtx, codec)
                self.outVideoStream?.pointee.id = Int32(fmtCtx.pointee.nb_streams - 1)
                
                if let stream = self.outVideoStream, avcodec_parameters_from_context(stream.pointee.codecpar, codecCtx) < 0 {
                    print("Failed to copy codec context parameters to video out stream")
                    return
                }
            }
            
            if let codec = self.audioCodec, let codecCtx = self.audioCodecContext {
                self.outAudioStream = avformat_new_stream(fmtCtx, codec)
                self.outAudioStream?.pointee.id = Int32(fmtCtx.pointee.nb_streams - 1)
             
                if let stream = self.outAudioStream, avcodec_parameters_from_context(stream.pointee.codecpar, codecCtx) < 0 {
                    print("Failed to copy codec context parameters to audio out stream")
                    return
                }
            }
            
            let flags = fmtCtx.pointee.oformat.pointee.flags
            if (flags & AVFMT_GLOBALHEADER) > 0 {
                fmtCtx.pointee.oformat.pointee.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
            }
            
            self.writeTSHeader()
            print("Muxer is ready...")
        }
        
    }
    
    func destoryMuxer() {
        if let ofCtx = self.outFMTCtx {
            av_write_trailer(ofCtx)
            if let pb = ofCtx.pointee.pb, ofCtx.pointee.flags & AVFMT_NOFILE == 0 {
                if let buff = pb.pointee.buffer {
                    free(buff)
                    pb.pointee.buffer = nil
                }
                avio_close(pb)
                ofCtx.pointee.pb = nil
            }
            avformat_free_context(ofCtx)
            self.outFMTCtx = nil
        }
    
    }
   
    private
    func isToWrite() -> AudioOrVideoToWriteType {
        
        guard self.encoderType == .both else {
            return self.encoderType == .video ? .video : .audio
        }
        
        guard let vCodecCtx = self.videoCodecContext, let aCodecCtx = self.audioCodecContext else {
            print("Codec context is not ready yet...")
            return .none
        }
        
        //同时编码音视频时，以音频捕获第一帧的时间为基准，确保视频同步于音频
        if self.displayTimeBase == 0 {
            print("Audio is not ready yet...")
            return .none
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
        let ret = av_compare_ts(self.videoNextPts, vCodecCtx.pointee.time_base, self.audioNextPts, aCodecCtx.pointee.time_base)
        print("vPts \(self.videoNextPts) - aPts: \(self.audioNextPts)")
        if ret <= 0 /*vCurTime <= aCurTime*/ {
            return .video
        }else {
            return .audio
        }
    }
    
    func muxer(packet: UnsafeMutablePointer<AVPacket>, stream: UnsafeMutablePointer<AVStream>, timebase: AVRational) -> Bool {
        
        guard let fmtCtx = self.outFMTCtx else {
            return false
        }
        
        av_packet_rescale_ts(packet, timebase, stream.pointee.time_base)
        packet.pointee.stream_index = stream.pointee.index
        
        /**
        * Write a packet to an output media file ensuring correct interleaving.
        *
        * @return 0 on success, a negative AVERROR on error. Libavformat will always
        *         take care of freeing the packet, even if this function fails.
        *
        */
        let ret = av_interleaved_write_frame(fmtCtx, packet)
        
        return ret == 0 ? true : false
    }
    
    
}

private func muxerCallback(opaque: UnsafeMutableRawPointer?, buff: UnsafeMutablePointer<UInt8>?, buffSize :Int32) -> Int32 {
       
    if buff != nil && buffSize > 0 {
        let encodedData = unsafeBitCast(malloc(Int(buffSize)), to: UnsafeMutablePointer<UInt8>.self)
        memcpy(encodedData, buff, Int(buffSize))
        if opaque != nil {
            let ffmpegEncoder = unsafeBitCast(opaque, to: FFmpegEncoder.self)
            ffmpegEncoder.onMuxerFinished?(encodedData, buffSize)
        }
    }
    
    return 0
}


