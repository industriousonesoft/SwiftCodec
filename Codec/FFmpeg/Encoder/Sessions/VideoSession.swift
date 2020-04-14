//
//  Codec.FFmpeg.Encoder.VideoSession.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

private let ErrorDomain = "FFmpeg:Video:Encoder"
private let Timebase = AVRational.init(num: 1, den: 90000)

extension AVFrame {
    var sliceArray: [UnsafePointer<UInt8>?] {
        mutating get {
             return [
                UnsafePointer<UInt8>(self.data.0),
                UnsafePointer<UInt8>(self.data.1),
                UnsafePointer<UInt8>(self.data.2),
                UnsafePointer<UInt8>(self.data.3),
                UnsafePointer<UInt8>(self.data.4),
                UnsafePointer<UInt8>(self.data.5),
                UnsafePointer<UInt8>(self.data.6),
                UnsafePointer<UInt8>(self.data.7)
            ]
        }
    }
    
    var mutablleSliceArray: [UnsafeMutablePointer<UInt8>?] {
        mutating get {
             return [
                UnsafeMutablePointer<UInt8>(self.data.0),
                UnsafeMutablePointer<UInt8>(self.data.1),
                UnsafeMutablePointer<UInt8>(self.data.2),
                UnsafeMutablePointer<UInt8>(self.data.3),
                UnsafeMutablePointer<UInt8>(self.data.4),
                UnsafeMutablePointer<UInt8>(self.data.5),
                UnsafeMutablePointer<UInt8>(self.data.6),
                UnsafeMutablePointer<UInt8>(self.data.7)
            ]
        }
    }
    
    var strideArray: [Int32] {
        mutating get {
            return [
                self.linesize.0,
                self.linesize.1,
                self.linesize.2,
                self.linesize.3,
                self.linesize.4,
                self.linesize.5,
                self.linesize.6,
                self.linesize.7
            ]
        }
    }
}

//MARK: - VideoSession
extension Codec.FFmpeg.Encoder {
    
    class VideoSession: NSObject {
        private(set) var codecCtx: UnsafeMutablePointer<AVCodecContext>?
          
        private var inFrame: UnsafeMutablePointer<AVFrame>?
        private var outFrame: UnsafeMutablePointer<AVFrame>?
        
        private var swsCtx: OpaquePointer?

        private var outVideoStream: UnsafeMutablePointer<AVStream>?
      
        private var displayTimeBase: Double = 0
        
        private(set) var inSize: CGSize = .zero
        private(set) var outSize: CGSize = .zero
        
        var onEncodedData: EncodedDataCallback? = nil
        var onEncodedPacket: EncodedPacketCallback? = nil
        
        init(config: Codec.FFmpeg.Video.Config) throws {
            super.init()
            self.outSize = config.outSize
            try self.createCodec(config: config)
            try self.createOutFrame(size: self.outSize)
        }
        
        deinit {
            self.onEncodedData = nil
            self.onEncodedPacket = nil
            self.destroyInFrame()
            self.destroyOutFrame()
            self.destroySwsCtx()
            self.destroyCodec()
        }
        
    }
}

extension Codec.FFmpeg.Encoder.VideoSession {
    
    func createCodec(config: Codec.FFmpeg.Video.Config) throws {
        
        #warning("Deprecated, No neccessary any more!")
        //avcodec_register_all()
        
        let codecId = config.codec.toAVCodecID()
        let codec = avcodec_find_encoder(codecId)
        
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Failed to create video codec context.")!
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
        codecCtx.pointee.pix_fmt = AV_PIX_FMT_YUV420P
        codecCtx.pointee.mb_cmp = FF_MB_DECISION_RD
        //CBR is default setting, VBR Setting blow:
        //context.pointee.flags |= AV_CODEC_FLAG_QSCALE
        //context.pointee.rc_max_rate =
        //context.pointee.rc_min_rate =
       
        guard avcodec_open2(codecCtx, codec, nil) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to open video avcodec.")!
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
        self.inFrame = try self.createFrame(pixFmt: SWIFT_AV_PIX_FMT_RGB32, size: size)
    }
    
    func destroyInFrame() {
        if let frame = self.inFrame {
            av_free(frame)
            self.inFrame = nil
        }
    }
    
    func createOutFrame(size: CGSize) throws {
        self.outFrame = try self.createFrame(pixFmt: AV_PIX_FMT_YUV420P, size: size)
    }
    
    func destroyOutFrame() {
        if let frame = self.outFrame {
            av_free(frame)
            self.outFrame = nil
        }
    }
 
    func createFrame(pixFmt: AVPixelFormat, size: CGSize) throws -> UnsafeMutablePointer<AVFrame>? {
        
        guard let frame = av_frame_alloc() else {
            throw NSError.error(ErrorDomain, reason: "Failed to alloc frame.")!
        }
        
        frame.pointee.format = pixFmt.rawValue
        frame.pointee.width = Int32(size.width)
        frame.pointee.height = Int32(size.height)
        frame.pointee.pts = 0
           
        let frameSize = av_image_get_buffer_size(pixFmt,  Int32(size.width), Int32(size.height), 1)
        if frameSize < 0 {
            throw NSError.error(ErrorDomain, reason: "Can not get the video output frame buffer size.")!
        }
           
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(frameSize))
        if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), buffer, AV_PIX_FMT_YUV420P, Int32(size.width), Int32(size.height), 1) < 0 {
            throw NSError.error(ErrorDomain, reason: "Can not get the video output frame buffer size.")!
        }
        
        return frame
    }

}

//MARK: - Sws Context
private
extension Codec.FFmpeg.Encoder.VideoSession {
    
    func createSwsCtx(inSize: CGSize, outSize: CGSize) throws {
        if let sws = sws_getContext(Int32(inSize.width), Int32(inSize.height), SWIFT_AV_PIX_FMT_RGB32, Int32(outSize.width), Int32(outSize.height), AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, nil, nil, nil) {
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
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double) throws {
         
        //let inDataArray = unsafeBitCast([rgbPixels], to: UnsafePointer<UnsafePointer<UInt8>?>?.self)
        //let inLineSizeArray = unsafeBitCast([self.inWidth * 4], to: UnsafePointer<Int32>.self)
        //print("Video display time: \(displayTime)")
            
        if __CGSizeEqualToSize(self.inSize, size) == false {
            self.destroyInFrame()
            self.destroySwsCtx()
            try self.createInFrame(size: size)
            try self.createSwsCtx(inSize: size, outSize: self.outSize)
            self.inSize = size
        }
        
        if self.displayTimeBase == 0 {
            self.displayTimeBase = displayTime
        }
        
        guard let codecCtx = self.codecCtx else {
            throw NSError.error(ErrorDomain, reason: "Audio Codec not initilized yet.")!
        }
        
        guard let outFrame = self.outFrame, let inFrame = self.inFrame else {
            throw NSError.error(ErrorDomain, reason: "Video Frame not initailized.")!
        }
      
        inFrame.pointee.data.0 = bytes
        //输入使用的是AV_PIX_FMT_RGB32: width x 4(RGBA有4个颜色通道个数) = bytesPerRow = stride
        inFrame.pointee.linesize.0 = Int32(size.width) * 4
       
        //TODO: Using libyuv to convert RGB32 to YUV420 is faster then sws_scale
        //Return the height of the output slice
        //不同于音频重采样，视频格式转换不影响视频采样率，所以转换前后的同一时间内采样数量不变
        let destSliceH = sws_scale(self.swsCtx, inFrame.pointee.sliceArray, inFrame.pointee.strideArray, 0, Int32(size.height), outFrame.pointee.mutablleSliceArray, outFrame.pointee.strideArray)
        
        if destSliceH > 0 {
            
            //累计采样数
            let duration = displayTime - self.displayTimeBase
            let nb_samples_count = Int64(duration * Double(Timebase.den))
            
            //这一步很关键！在未知输入视频的帧率或者帧率是一个动态值时，使用视频采样率（一般都是90K）作为视频量增幅的参考标准
            //然后，将基于采样频率的增量计数方式转换为基于当前编码帧率的增量计数方式
            outFrame.pointee.pts = av_rescale_q(nb_samples_count, Timebase, codecCtx.pointee.time_base)
         
//                print("[Video] encode for now...")
            self.encode(self.outFrame!, in: codecCtx) { (packet, error) in
                
                if let onEncoded = self.onEncodedData {
                    if packet != nil {
                        let size = Int(packet!.pointee.size)
                        let encodedBytes = unsafeBitCast(malloc(size), to: UnsafeMutablePointer<UInt8>.self)
                        memcpy(encodedBytes, packet!.pointee.data, size)
                        onEncoded((encodedBytes, Int32(size)), nil)
                    }else {
                        onEncoded(nil, error)
                    }
                    
                }
                
                if let onEncoded = self.onEncodedPacket {
                    if packet != nil {
                        onEncoded(packet!, nil)
                    }else {
                        onEncoded(nil, error)
                    }
                }else {
                    av_packet_unref(packet)
                }
            }
            
        }
        
    }
    
    private
    func encode(_ frame: UnsafeMutablePointer<AVFrame>, in codecCtx: UnsafeMutablePointer<AVCodecContext>, onFinished: (UnsafeMutablePointer<AVPacket>?, Error?)->Void) {
  
        var videoPacket = AVPacket.init()
        withUnsafeMutablePointer(to: &videoPacket) { (ptr) in
            
            av_init_packet(ptr)
            
            var ret = avcodec_send_frame(codecCtx, frame)
            if ret < 0 {
                onFinished(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error about sending a packet for video encoding.")!)
                return
            }
            
            ret = avcodec_receive_packet(codecCtx, ptr)
            if ret == 0 {
                //更新packet与frame的present timestamp一致，用于muxing时音视频同步校准
                ptr.pointee.pts = frame.pointee.pts
                onFinished(ptr, nil)
            }else {
                if ret == SWIFT_AV_ERROR_EOF {
                    print("avcodec_recieve_packet() encoder flushed...")
                }else if ret == SWIFT_AV_ERROR_EAGAIN {
                    print("avcodec_recieve_packet() need more input...")
                }else if ret < 0 {
                    onFinished(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when encoding video.")!)
                }
                av_packet_unref(ptr)
            }
    
        }
     
    }
}
