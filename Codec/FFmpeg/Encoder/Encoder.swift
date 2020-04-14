//
//  Encoder.swift
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

import Foundation

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
    
    internal var displayTimeBase: Double = 0
    internal var isWroteHeader: Bool = false

    //Muxer
    internal lazy var muxingQueue: DispatchQueue = {
        DispatchQueue.init(label: "com.zdnet.encoder.muxingQueue")
    }()
    internal var outFMTCtx: UnsafeMutablePointer<AVFormatContext>?
    
    //Video
    internal var videoCodec: UnsafeMutablePointer<AVCodec>?
    internal var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    
    internal var videoInFrame: UnsafeMutablePointer<AVFrame>?
    internal var videoOutFrame: UnsafeMutablePointer<AVFrame>?
  
    internal var swsContext: OpaquePointer?

    internal var outVideoStream: UnsafeMutablePointer<AVStream>?
    internal var videoNextPts: Int64 = 0
    
    //Audio
    internal var audioCodec: UnsafeMutablePointer<AVCodec>?
    internal var audioCodecContext: UnsafeMutablePointer<AVCodecContext>?

    internal var audioOutFrame: UnsafeMutablePointer<AVFrame>?

    internal var covertedSampleBuffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
    internal var audioFifo: OpaquePointer?
    
    internal var swrContext: OpaquePointer?
    
    internal var outAudioStream: UnsafeMutablePointer<AVStream>?
    
    //General
    internal var inAudioDesc: AudioDescriptionTuple?
    internal var outAudioDesc: AudioDescriptionTuple?
    
    internal var audioSampleCount: Int64 = 0
    internal var audioNextPts: Int64 = 0
    internal var frameSize: Int32 = 0
    private(set) var encoderType: EncoderType!
    
    public private(set) var inSize: CGSize = .zero
    public private(set) var outSize: CGSize = .zero
       
    public private(set) var encodeVideo: Bool = true
    public private(set) var encodeAudio: Bool = true
    
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
    
    private
    func createSwsContect(inSize: CGSize, outSize: CGSize) throws {
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
            
//            let flags = fmtCtx.pointee.oformat.pointee.flags
//            if (flags & AVFMT_GLOBALHEADER) > 0 {
//                fmtCtx.pointee.oformat.pointee.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
//            }
            
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


