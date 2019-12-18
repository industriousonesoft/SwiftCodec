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

public typealias OnResampleFinishedClouser = (UnsafeMutablePointer<UInt8>, Int32) -> Void
public typealias OnEncodeFinishedClouser = (UnsafeMutablePointer<UInt8>, Int32) -> Void
public typealias OnMuxerFinishedClouser = (UnsafeMutablePointer<UInt8>, Int32) -> Void
public typealias OnEncodedFailuerClouser = (NSError?)->Void

private let SWIFT_AV_PIX_FMT_RGB32 = AVPixelFormat(FFmepgWrapperOCBridge.avPixelFormatRGB32())
private let SWIFT_AV_ERROR_EOF = FFmepgWrapperOCBridge.avErrorEOF()
private let SWIFT_AV_ERROR_EAGAIN = FFmepgWrapperOCBridge.avErrorEagain()

public let SWIFT_AV_SAMPLE_FMT_S16: Int32 = AV_SAMPLE_FMT_S16.rawValue
public let SWIFT_AV_SAMPLE_FMT_S16P: Int32 = AV_SAMPLE_FMT_S16P.rawValue
public let SWIFT_AV_SAMPLE_FMT_FLT: Int32 = AV_SAMPLE_FMT_FLT.rawValue
public let SWIFT_AV_SAMPLE_FMT_FLTP: Int32 = AV_SAMPLE_FMT_FLTP.rawValue

public typealias AudioDescriptionTuple = (sampleRate: Int32, channels: Int32, bitsPerChannel: Int32, sampleFormat: Int32)

public class FFmpegEncoder: NSObject {
    
    public private(set) var inWidth: Int32 = 0
    public private(set) var inHeight: Int32 = 0
    public private(set) var outWidth: Int32 = 0
    public private(set) var outHeight: Int32 = 0
    
    //Muxer
    private var outFMTCtx: UnsafeMutablePointer<AVFormatContext>?
    
    //Video
    private var videoCodec: UnsafeMutablePointer<AVCodec>?
    private var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    
    private var videoInFrame: UnsafeMutablePointer<AVFrame>?
    private var videoInFrameBuffer: UnsafeMutablePointer<UInt8>?
    
    private var videoOutFrame: UnsafeMutablePointer<AVFrame>?
    private var videoOutFrameBuffer: UnsafeMutablePointer<UInt8>?

    private var videoPacket = AVPacket.init()
    private var swsContext: OpaquePointer?

    private var outVideoStream: UnsafeMutablePointer<AVStream>?
    
    //Audio
    private var audioCodec: UnsafeMutablePointer<AVCodec>?
    private var audioCodecContext: UnsafeMutablePointer<AVCodecContext>?

    private var audioOutFrame: UnsafeMutablePointer<AVFrame>?
    private var audioOutFrameBuffer: UnsafeMutablePointer<UInt8>?
   
    private var audioPacket = AVPacket.init()
    private var swrContext: OpaquePointer?
    
    private var outAudioStream: UnsafeMutablePointer<AVStream>?
    
    private var inAudioDesc: AudioDescriptionTuple?
    private var outAudioDesc: AudioDescriptionTuple?
    
    //Callback
    public var onVideoEncodeFinished: OnEncodeFinishedClouser?
    public var onAudioEncodeFinished: OnEncodeFinishedClouser?
    public var onAudioResampleFinished: OnResampleFinishedClouser?
    public var onMuxerFinished: OnMuxerFinishedClouser?
    public var onVideoEncoderFaiure: OnEncodedFailuerClouser?
    public var onAudioEncoderFaiure: OnEncodedFailuerClouser?
    
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
                  
    public override init() {
        super.init()
    }
    
    deinit {
        self.destory()
    }
    
    public func destory() {
        self.destroyAudioEncoder()
        self.destroyVideoEncoder()
        self.destoryMuxer()
    }
    
}

//MARK: Encode Video
extension FFmpegEncoder {
    
    public func initAudioEncoder(inAudioDesc: AudioDescriptionTuple, outAudioDesc: AudioDescriptionTuple) -> Bool {
        
        var hasError = false
        
        defer {
            if hasError == true {
                self.destroyAudioEncoder()
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
            context.pointee.bit_rate = 128000
            self.audioCodecContext = context
        }else {
            print("Can not create audio codec context...")
            hasError = true
            return false
        }
        
        if avcodec_open2(self.audioCodecContext!, self.audioCodec!, nil) < 0 {
            print("Can not open audio avcodec...")
            hasError = true
            return false
        }
        
        //outFrame
        if let frame = av_frame_alloc() {
            frame.pointee.format = outAudioDesc.sampleFormat
            
            let nb_samples = self.audioCodecContext!.pointee.frame_size
            frame.pointee.nb_samples = nb_samples

            let size = av_samples_get_buffer_size(nil, outAudioDesc.channels, nb_samples, AVSampleFormat(outAudioDesc.sampleFormat), 1)
            if size < 0 {
                print("Can not get the output sampele buffer size...")
                hasError = true
                return false
            }
            
            self.audioOutFrameBuffer = unsafeBitCast(malloc(Int(size)), to: UnsafeMutablePointer<UInt8>.self)
            
            if avcodec_fill_audio_frame(frame, outAudioDesc.channels, AVSampleFormat(outAudioDesc.sampleFormat), self.audioOutFrameBuffer, size, 1) < 0 {
                print("Can not fill output audio frame...")
                hasError = true
                return false
            }
            
            self.audioOutFrame = frame
            
        }else {
            print("Can not create audio output frame...")
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
        
        return true
    }
    
    public func destroyAudioEncoder() {
    
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
        if let frame = self.audioOutFrame {
            av_free(frame)
            self.audioOutFrame = nil
        }
        if let frameBuffer = self.audioOutFrameBuffer {
            free(frameBuffer)
            self.audioOutFrameBuffer = nil
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
    
    public func encode(pamBytes: UnsafeMutablePointer<UInt8>, bytesLen: Int32) {
        
        if let swr = self.swrContext, let codecCtx = self.audioCodecContext, let inAudioDesc = self.inAudioDesc, let outAudioDesc = self.outAudioDesc {
            
            var srcBuff = unsafeBitCast(pamBytes, to: UnsafePointer<UInt8>?.self)
        
            let src_nb_samples = bytesLen/(inAudioDesc.channels * inAudioDesc.bitsPerChannel / 8)/*2 channel, 32 bits per channel(SWIFT_AV_SAMPLE_FMT_FLT)*/
            let dst_nb_samples = self.audioOutFrame!.pointee.nb_samples
            
            /* 使用下面公式计算并更改audioOutFrame的nb_samples值会导致编码失败（-22)，改为在定义audioOutFrame使用self.audioCodecContext!.pointee.frame_size作为nb_samples值
             let dst_nb_samples = av_rescale_rnd(swr_get_delay(swr, Int64(inAudioDesc.sampleRate)) + Int64(src_nb_samples), Int64(outAudioDesc.sampleRate), Int64(inAudioDesc.sampleRate), AV_ROUND_UP)
            guard self.updateAudioOutFrame(nb_samples: Int32(dst_nb_samples)) == true else {
                self.onAudioEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(-1), userInfo: [NSLocalizedDescriptionKey : "Error about update audio out frame for rasampling."]))
                return
            }
             */
            
            let nb_samples = swr_convert(swr, &self.audioOutFrameBuffer, Int32(dst_nb_samples), &srcBuff, src_nb_samples)
            
            if nb_samples > 0 {
                
                if let onResample = self.onAudioResampleFinished {
//                    let size = av_samples_get_buffer_size(nil, self.audioCodecContext!.pointee.channels, nb_samples, AVSampleFormat(outSampleFormat), 1)
                    let size = nb_samples * outAudioDesc.channels * (outAudioDesc.bitsPerChannel / 8)
                    onResample(self.audioOutFrameBuffer!, size)
                }
                
                av_init_packet(UnsafeMutablePointer<AVPacket>(&self.audioPacket))
                                
                defer {
                    av_packet_unref(UnsafeMutablePointer<AVPacket>(&self.audioPacket))
                }
                
                //FIXME: How to set pts of audio frame
                self.audioOutFrame!.pointee.pts += 1
             
                var ret = avcodec_send_frame(codecCtx, self.audioOutFrame)
                if ret < 0 {
                    self.onAudioEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error about sending a packet for audio encoding."]))
                    return
                }
                
                ret = avcodec_receive_packet(self.audioCodecContext, UnsafeMutablePointer<AVPacket>(&self.audioPacket))
                if ret == SWIFT_AV_ERROR_EOF {
                    print("avcodec_recieve_packet() encoder flushed...")
                }else if ret == SWIFT_AV_ERROR_EAGAIN {
                    print("avcodec_recieve_packet() need more input...")
                }else if ret < 0 {
                    self.onAudioEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding audio."]))
                    return
                }
                
                if ret == 0 {
                    
//                    print("Encoded audio successfully...")
                      
                    if let onEncoded = self.onAudioEncodeFinished {
                        let packetSize = Int(self.audioPacket.size)
                        let encodedBytes = unsafeBitCast(malloc(packetSize), to: UnsafeMutablePointer<UInt8>.self)
                        memcpy(encodedBytes, self.audioPacket.data, packetSize)
                        onEncoded(encodedBytes, Int32(packetSize))
                    }
                    
                    if let ofCtx = self.outFMTCtx, self.onMuxerFinished != nil {
                        self.audioPacket.stream_index = self.outAudioStream!.pointee.index
                        av_packet_rescale_ts(&self.audioPacket, self.audioCodecContext!.pointee.time_base, self.outAudioStream!.pointee.time_base)
                        av_interleaved_write_frame(ofCtx, &self.audioPacket)
                    }
                    
                }
            }
        }
    }
    
}

//MARK: Encode Video
extension FFmpegEncoder {
    
    public func initVideoEncoder(inWidth: Int32, inHeight: Int32, outWidth: Int32, outHeight: Int32, bitrate: Int64) -> Bool {
            
        var hasError = false
        
        defer {
            if hasError == true {
                self.destroyVideoEncoder()
            }
        }
        
        self.inWidth = inWidth
        self.inHeight = inHeight
        self.outWidth = outWidth
        self.outHeight = outHeight
        
        //Deprecated, No neccessary any more!
//        avcodec_register_all()
        let codecId: AVCodecID = AV_CODEC_ID_MPEG1VIDEO
        if let codec = avcodec_find_encoder(codecId) {
            self.videoCodec = codec
        }else {
            print("Can not create video codec...")
            hasError = true
            return false
        }
        
        if let context = avcodec_alloc_context3(self.videoCodec) {
            context.pointee.codec_id = codecId
            context.pointee.codec_type = AVMEDIA_TYPE_VIDEO
            context.pointee.dct_algo = FF_DCT_FASTINT
            context.pointee.bit_rate = bitrate
            context.pointee.width = outWidth
            context.pointee.height = outHeight
            context.pointee.time_base.num = 1
            context.pointee.time_base.den = 25
            context.pointee.gop_size = 60
            context.pointee.max_b_frames = 0 //Drop out B frame
            context.pointee.pix_fmt = AV_PIX_FMT_YUV420P
            context.pointee.mb_cmp = FF_MB_DECISION_RD
            self.videoCodecContext = context
        }else {
            print("Can not create video codec context...")
            hasError = true
            return false
        }
        
        if  avcodec_open2(self.videoCodecContext!, self.videoCodec!, nil) < 0 {
            print("Can not open video avcodec...")
            hasError = true
            return false
        }
        
        //InFrame
        if let frame = av_frame_alloc() {
            frame.pointee.format = SWIFT_AV_PIX_FMT_RGB32.rawValue
            frame.pointee.width = inWidth
            frame.pointee.height = inHeight
            frame.pointee.pts = 0
            
            let frameSize = av_image_get_buffer_size(AV_PIX_FMT_YUV420P, outWidth, outHeight, 1)
            if frameSize < 0 {
                print("Can not get the buffer size...")
                hasError = true
                return false
            }
            
            self.videoInFrameBuffer = unsafeBitCast(malloc(Int(frameSize)), to: UnsafeMutablePointer<UInt8>.self)
            
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), self.videoInFrameBuffer, SWIFT_AV_PIX_FMT_RGB32, inWidth, inHeight, 1) < 0 {
                print("Can not fill input frame...")
                hasError = true
                return false
            }
            
            self.videoInFrame = frame
            
        }else {
            print("Can not create video input frame...")
            hasError = true
            return false
        }
        
        //OutFrame
        if let frame = av_frame_alloc() {
            frame.pointee.format = AV_PIX_FMT_YUV420P.rawValue
            frame.pointee.width = outWidth
            frame.pointee.height = outHeight
            frame.pointee.pts = 0
            
            let frameSize = av_image_get_buffer_size(AV_PIX_FMT_YUV420P, outWidth, outHeight, 1)
            if frameSize < 0 {
                print("Can not get the YUV420P buffer size...")
                hasError = true
                return false
            }
            
            self.videoOutFrameBuffer = unsafeBitCast(malloc(Int(frameSize)), to: UnsafeMutablePointer<UInt8>.self)
            
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), self.videoOutFrameBuffer, AV_PIX_FMT_YUV420P, outWidth, outHeight, 1) < 0 {
                print("Can not fill video output frame...")
                hasError = true
                return false
            }
            
            self.videoOutFrame = frame
            
        }else {
            print("Can not create video output frame...")
            hasError = true
            return false
        }
    
        if let sws = sws_getContext(inWidth, inHeight, SWIFT_AV_PIX_FMT_RGB32, outWidth, outHeight, AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, nil, nil, nil) {
             self.swsContext = sws
        }else {
            print("Can not create sws context...")
            hasError = true
            return false
        }
      
        self.initMuxer()
    
        return true
    }
    
    func destroyVideoEncoder() {
        
        if let sws = self.swsContext {
            sws_freeContext(sws)
            self.swsContext = nil
        }
        if let context = self.videoCodecContext {
            avcodec_close(context)
            avcodec_free_context(&self.videoCodecContext)
            self.videoCodecContext = nil
        }
        if let frame = self.videoOutFrame {
            av_free(frame)
            self.videoOutFrame = nil
        }
        if let frameBuffer = self.videoOutFrameBuffer {
            free(frameBuffer)
            self.videoOutFrameBuffer = nil
        }
        if let frame = self.videoInFrame {
            av_free(frame)
            self.videoInFrame = nil
        }
        if let frameBuffer = self.videoInFrameBuffer {
            free(frameBuffer)
            self.videoInFrameBuffer = nil
        }
    }
    
    public func encode(rgbPixels: UnsafeMutablePointer<UInt8>) {
      
//        let inDataArray = unsafeBitCast([rgbPixels], to: UnsafePointer<UnsafePointer<UInt8>?>?.self)
//        let inLineSizeArray = unsafeBitCast([self.inWidth * 4], to: UnsafePointer<Int32>.self)

        if self.videoOutFrame != nil && self.videoInFrame != nil {
            
            self.videoInFrame!.pointee.data.0 = rgbPixels
            //RGB32
            self.videoInFrame!.pointee.linesize.0 = self.inWidth * 4
            
            //Convert RGB32 to YUV420
            //Return the height of the output slice
            let destSliceH = sws_scale(self.swsContext, self.videoSrcSliceArray, self.videoSrcStrideArray, 0, self.inHeight, self.videoDstSliceArray, self.videoDstStrideArray)
            
            if destSliceH > 0 {
           
                //Why do pts here need to add 1?
                self.videoOutFrame!.pointee.pts += 1
                
                av_init_packet(UnsafeMutablePointer<AVPacket>(&self.videoPacket))
                
                defer {
                    av_packet_unref(UnsafeMutablePointer<AVPacket>(&self.videoPacket))
                }
                
                var ret = avcodec_send_frame(self.videoCodecContext, self.videoOutFrame)
                if ret < 0 {
                    self.onVideoEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error about sending a packet for video encoding."]))
                    return
                }
                
                ret = avcodec_receive_packet(self.videoCodecContext, UnsafeMutablePointer<AVPacket>(&self.videoPacket))
                if ret == SWIFT_AV_ERROR_EOF {
                    print("avcodec_recieve_packet() encoder flushed...")
                }else if ret == SWIFT_AV_ERROR_EAGAIN {
                    print("avcodec_recieve_packet() need more input...")
                }else if ret < 0 {
                    self.onVideoEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding video."]))
                    return
                }
                
                if ret == 0 {
//                        print("Encoded video successfully...")
                    
                    if self.videoOutFrame?.pointee.key_frame == 1 {
                        self.videoPacket.flags |= AV_PKT_FLAG_KEY
                    }
                    
                    if let onEncoded = self.onVideoEncodeFinished {
                        let packetSize = Int(self.videoPacket.size)
                        let encodedBytes = unsafeBitCast(malloc(packetSize), to: UnsafeMutablePointer<UInt8>.self)
                        memcpy(encodedBytes, self.videoPacket.data, packetSize)
                        onEncoded(encodedBytes, Int32(packetSize))
                    }
                    
                    if let ofCtx = self.outFMTCtx, self.onMuxerFinished != nil {
                    
                        self.videoPacket.stream_index = self.outVideoStream!.pointee.index
                        av_packet_rescale_ts(&self.videoPacket, self.videoCodecContext!.pointee.time_base, self.outVideoStream!.pointee.time_base)
                        av_interleaved_write_frame(ofCtx, &self.videoPacket)

                    }
                    
                }
            }
           
        }else {
            self.onVideoEncoderFaiure?(NSError.init(domain: "FFmpegEncoder", code: Int(-1), userInfo: [NSLocalizedDescriptionKey : "Encoder not initailized."]))
        }
        
    }
}

//MARK: Muxer
extension FFmpegEncoder {
    
    func initMuxer() {
        
        let ioBufferSize: Int = 512*1024 //32768
        let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: ioBufferSize)
        let writable: Int = 1
        let ioCtx = avio_alloc_context(buff, Int32(ioBufferSize), Int32(writable), unsafeBitCast(self, to: UnsafeMutableRawPointer.self), nil, muxerCallback, nil)
        
        if avformat_alloc_output_context2(&outFMTCtx, nil, "mpegts", nil) < 0 {
            print("Could not create output context.")
            return
        }
        
        if let fmtCtx = self.outFMTCtx {
            
            fmtCtx.pointee.pb = ioCtx
            fmtCtx.pointee.flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_NOFILE | AVFMT_FLAG_FLUSH_PACKETS
            
            if let codec = self.videoCodec, let codecCtx = self.videoCodecContext {
                self.outVideoStream = avformat_new_stream(fmtCtx, codec)
                self.outVideoStream?.pointee.id = Int32(fmtCtx.pointee.nb_streams - 1)
                
                codecCtx.pointee.codec_tag = 0
                if let stream = self.outVideoStream, avcodec_parameters_from_context(stream.pointee.codecpar, codecCtx) < 0 {
                    print("Failed to copy codec context parameters to video out stream")
                    return
                }
            }
            
            if let codec = self.audioCodec, let codecCtx = self.audioCodecContext {
                self.outAudioStream = avformat_new_stream(fmtCtx, codec)
                self.outAudioStream?.pointee.id = Int32(fmtCtx.pointee.nb_streams - 1)
              
                codecCtx.pointee.codec_tag = 0
                if let stream = self.outAudioStream, avcodec_parameters_from_context(stream.pointee.codecpar, codecCtx) < 0 {
                    print("Failed to copy codec context parameters to audio out stream")
                    return
                }
            }
            
            let flags = fmtCtx.pointee.oformat.pointee.flags
            if (flags & AVFMT_GLOBALHEADER) > 0 {
                fmtCtx.pointee.oformat.pointee.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
            }
            
            av_dump_format(fmtCtx, 0, nil, 1)
            
            if avformat_write_header(fmtCtx, nil) < 0 {
                print("Error occurred when writing header.")
                return
            }
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
