//
//  Codec.FFmpeg.Encoder.VideoSession.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

private let ErrorDomain = "FFmpeg:Video:Encoder"
private let SampleTimebase = AVRational.init(num: 1, den: 90000)

//MARK: - VideoSession
extension Codec.FFmpeg.Encoder {
    
    class VideoSession {
        private(set) var codecCtx: UnsafeMutablePointer<AVCodecContext>?
        private var inFrame: UnsafeMutablePointer<AVFrame>?
        private var outFrame: UnsafeMutablePointer<AVFrame>?
        private var packet: UnsafeMutablePointer<AVPacket>?
        
        private var swsCtx: OpaquePointer?

        private var outVideoStream: UnsafeMutablePointer<AVStream>?
      
        private var displayTimeBase: Double = 0
        
        private(set) var inSize: CGSize = .zero
        private(set) var outSize: CGSize = .zero
        
        private(set) var lastPts: Int64 = -1
        private var encodeQueue: DispatchQueue
        
        init(config: Codec.FFmpeg.Video.Config, encodeIn queue: DispatchQueue? = nil) throws {
            self.encodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.VideoSession.encode.queue")
            self.outSize = config.outSize
            try self.createCodec(config: config)
            try self.createOutFrame(size: self.outSize)
            try self.createOutPakcet()
        }
        
        deinit {
            self.lastPts = -1
            self.destroyInFrame()
            self.destroyOutFrame()
            self.destroyOutPacket()
            self.destroySwsCtx()
            self.destroyCodec()
        }
        
    }
}

extension Codec.FFmpeg.Encoder.VideoSession {
    
    func createCodec(config: Codec.FFmpeg.Video.Config) throws {
        
        #warning("Deprecated, No neccessary any more!")
        //avcodec_register_all()
        
        let codecId = config.codec.codecID()
        let codec = avcodec_find_encoder(codecId)
        
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Failed to create video encode context.")!
        }
        codecCtx.pointee.codec_id = codecId
        codecCtx.pointee.codec_type = AVMEDIA_TYPE_VIDEO
        codecCtx.pointee.dct_algo = FF_DCT_FASTINT
        codecCtx.pointee.bit_rate = config.bitRate
        codecCtx.pointee.width = Int32(config.outSize.width)
        codecCtx.pointee.height = Int32(config.outSize.height)
        codecCtx.pointee.time_base.num = 1
        //All the fps supported by mpeg1: 0, 23.976, 24, 25, 29.97, 30, 50, 59.94, 60
        codecCtx.pointee.time_base.den = config.fps
        codecCtx.pointee.gop_size = config.gopSize // 2s: 2 * 25
        //Drop out B frame
        if config.dropB == true {
            codecCtx.pointee.max_b_frames = 0
        }
        codecCtx.pointee.pix_fmt = config.codec.pixelFormat()
        codecCtx.pointee.mb_cmp = FF_MB_DECISION_RD
        //CBR is default setting, VBR Setting blow:
        //context.pointee.flags |= AV_CODEC_FLAG_QSCALE
        //context.pointee.rc_max_rate =
        //context.pointee.rc_min_rate =
       
        guard avcodec_open2(codecCtx, codec, nil) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to open video encoder.")!
        }
        
        self.codecCtx = codecCtx
        
    }
    
    func destroyCodec() {
        if let ctx = self.codecCtx {
            avcodec_close(ctx)
            avcodec_free_context(&self.codecCtx)
            self.codecCtx = nil
        }
    }
}

//MARK: - Frame
private
extension Codec.FFmpeg.Encoder.VideoSession {
    
    func createInFrame(size: CGSize) throws {
        //编码过程中，输出frame指向内存块是动态的，因此不必在初始化时创建（fill = false）
        self.inFrame = try self.createFrame(pixFmt: Codec.FFmpeg.SWIFT_AV_PIX_FMT_RGB32, size: size, fillIfNecessary: false)
    }
    
    func fillInFrame(bytes: UnsafeMutablePointer<UInt8>, size: CGSize) -> Bool {
        guard let frame = self.inFrame else {
            return false
        }
        return av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), bytes, Codec.FFmpeg.SWIFT_AV_PIX_FMT_RGB32, Int32(size.width), Int32(size.height), 1) > 0
    }
    
    func destroyInFrame() {
        if self.inFrame != nil {
            av_frame_free(&self.inFrame)
            self.inFrame = nil
        }
    }
    
    func createOutFrame(size: CGSize) throws {
        //编码过程中，输出frame指向内存块是固定的，因此在初始化时创建（fill = true）
        self.outFrame = try self.createFrame(pixFmt: AV_PIX_FMT_YUV420P, size: size, fillIfNecessary: true)
    }
    
    func destroyOutFrame() {
        if self.outFrame != nil {
            av_frame_free(&self.outFrame)
            self.outFrame = nil
        }
    }
 
    func createFrame(pixFmt: AVPixelFormat, size: CGSize, fillIfNecessary: Bool) throws -> UnsafeMutablePointer<AVFrame>? {
        
        guard let frame = av_frame_alloc() else {
            throw NSError.error(ErrorDomain, reason: "Failed to alloc frame.")!
        }
        frame.pointee.format = pixFmt.rawValue
        frame.pointee.width = Int32(size.width)
        frame.pointee.height = Int32(size.height)
        frame.pointee.pts = 0
        
        if fillIfNecessary == true {
            let bufferSize = av_image_get_buffer_size(pixFmt,  Int32(size.width), Int32(size.height), 1)
            if bufferSize < 0 {
                throw NSError.error(ErrorDomain, reason: "Can not get the video output frame buffer size.")!
            }
               
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferSize))
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), buffer, pixFmt, Int32(size.width), Int32(size.height), 1) < 0 {
                throw NSError.error(ErrorDomain, reason: "Faild to initialize out frame buffer.")!
            }
        }
        return frame
    }
    
}

//MARK: - AVPacket
private
extension Codec.FFmpeg.Encoder.VideoSession {
    
    func createOutPakcet() throws {
        guard let packet = av_packet_alloc() else {
            throw NSError.error(ErrorDomain, reason: "Failed to alloc packet.")!
        }
        self.packet = packet
    }
    
    func destroyOutPacket() {
        if self.packet != nil {
            av_packet_free(&self.packet)
            self.packet = nil
        }
    }
}

//MARK: - Sws Context
private
extension Codec.FFmpeg.Encoder.VideoSession {

    func createSwsCtx(inSize: CGSize, outSize: CGSize) throws {
        if let sws = sws_getContext(Int32(inSize.width), Int32(inSize.height), Codec.FFmpeg.SWIFT_AV_PIX_FMT_RGB32, Int32(outSize.width), Int32(outSize.height), AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, nil, nil, nil) {
            self.swsCtx = sws
        }else {
            throw NSError.error(ErrorDomain, reason: "Can not create sws context.")!
        }
    }
    
    func destroySwsCtx() {
        if let sws = self.swsCtx {
            sws_freeContext(sws)
            self.swsCtx = nil
        }
    }
}

//MARK: - Encode
extension Codec.FFmpeg.Encoder.VideoSession {
    
    func fill(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, onFinished: @escaping (Error?)-> Void) {
        self.encodeQueue.async { [unowned self] in
            self.innerFill(bytes: bytes, size: size, onFinished: onFinished)
        }
    }
    
    private
    func innerFill(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, onFinished: (Error?)-> Void) {
        
         //输入数据尺寸出现变化时更新格式转换器
        if __CGSizeEqualToSize(self.inSize, size) == false {
            self.destroyInFrame()
            self.destroySwsCtx()
            do {
                try self.createInFrame(size: size)
                try self.createSwsCtx(inSize: size, outSize: self.outSize)
            } catch let err {
                onFinished(err)
            }
            self.inSize = size
        }
          
        guard let outFrame = self.outFrame, let inFrame = self.inFrame else {
            onFinished(NSError.error(ErrorDomain, reason: "Video Frame not initailized."))
            return
        }
        
//            inFrame.pointee.data.0 = bytes
//            //输入使用的是AV_PIX_FMT_RGB32: width x 4(RGBA有4个颜色通道个数) = bytesPerRow = stride
//            inFrame.pointee.linesize.0 = Int32(size.width) * 4
        guard self.fillInFrame(bytes: bytes, size: size) else {
            onFinished(NSError.error(ErrorDomain, reason: "Failed to fill in frame buffer."))
            return
        }
        //TODO: Using libyuv to convert RGB32 to YUV420 is faster then sws_scale
        //Return the height of the output slice
        //不同于音频重采样，视频格式转换不影响视频采样率，所以转换前后的同一时间内采样数量不变
        let destSliceH = sws_scale(self.swsCtx, inFrame.pointee.sliceArray, inFrame.pointee.strideArray, 0, Int32(size.height), outFrame.pointee.mutablleSliceArray, outFrame.pointee.strideArray)
          
        if destSliceH > 0 {
            onFinished(nil)
        }else {
            onFinished(NSError.error(ErrorDomain, reason: "Failed to convert frame format."))
        }

    }
    
    func encode(displayTime: Double, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedPacketCallback) {
        self.encodeQueue.async { [unowned self] in
            self.innerEncode(displayTime: displayTime, onEncoded: onEncoded)
        }
    }
    
    private
    func innerEncode(displayTime: Double, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedPacketCallback) {
       
        guard let codecCtx = self.codecCtx else {
            onEncoded(nil, NSError.error(ErrorDomain, reason: "Audio Codec not initilized yet."))
            return
        }
        
        if self.displayTimeBase == 0 {
            self.displayTimeBase = displayTime
        }
        
        //累计采样时长
        let elapseTime = displayTime - self.displayTimeBase
        //累计采样数
        //两种计算pts的方法，本质上是一样的。第一种更精确一些。
        //计算pts方法1：
        //这一步很关键！在未知输入视频的帧率或者帧率是一个动态值时，使用视频采样率（一般都是90K）作为视频量增幅的参考标准
        let nb_samples_count = Int64(elapseTime * Double(SampleTimebase.den))
        //然后，将基于采样频率的增量计数方式转换为基于当前编码帧率的增量计数方式
        let pts = av_rescale_q(nb_samples_count, SampleTimebase, codecCtx.pointee.time_base)
        
        //计算pts方法2：不够精确
//        let pts = Int64(Double(codecCtx.pointee.time_base.den) * elapseTime)
        
//        print("[Video] pts: \(elapseTime) - \(pts) - \(Int32(pts2))")
        
        //如果前后两帧间隔时间很短，可能会出现计算出的pts是一样的，此处过滤一下
        if pts <= self.lastPts {
            return
        }
        
//        print("[Video] encode for now...: \(elapseTime) - \(nb_samples_count) - \(pts)")

        guard let outFrame = self.outFrame else {
            onEncoded(nil, NSError.error(ErrorDomain, reason: "Encode Video Frame not initailized."))
            return
        }
    
        self.lastPts = pts
        outFrame.pointee.pts = pts
        
        self.encode(outFrame, in: codecCtx, onFinished: onEncoded)
        
    }
    
    private
    func encode(_ frame: UnsafeMutablePointer<AVFrame>, in codecCtx: UnsafeMutablePointer<AVCodecContext>, onFinished: Codec.FFmpeg.Encoder.EncodedPacketCallback) {
        
        guard let packet = self.packet else {
            onFinished(nil, NSError.error(ErrorDomain, reason: "Encode Video Packet not initailized."))
            return
        }
        var ret = avcodec_send_frame(codecCtx, frame)
        
        if ret < 0 {
            onFinished(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when sending frame.")!)
            return
        }

        //Reset to default values
        av_init_packet(packet)
        
        ret = avcodec_receive_packet(codecCtx, packet)
        
        if ret == 0 {
            //Filter: Only muxing packet with available pts and dts, otherwise do nothing!
            if packet.pointee.pts != Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE
                && packet.pointee.dts != Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE {
                
                //TODO: How to change keyframe interval in ffmpeg？It seems every frame is key frame for now.
                if frame.pointee.key_frame == 1 {
                    packet.pointee.flags |= AV_PKT_FLAG_KEY
                }
//                print("Muxing Video Packet: \(frame.pointee.pts) - \(packet.pointee.pts) - \(packet.pointee.dts)")
                onFinished(packet, nil)
            }else {
//                print("Drop Video Packet: \(frame.pointee.pts) - \(packet.pointee.pts) - \(packet.pointee.dts)")
            }
        }else {
            if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EOF {
                print("avcodec_recieve_packet() encoder flushed...")
            }else if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EAGAIN {
                print("avcodec_recieve_packet() need more input...")
            }else if ret < 0 {
                onFinished(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when encoding video.")!)
                av_packet_unref(packet)
            }
        }
    }
}
