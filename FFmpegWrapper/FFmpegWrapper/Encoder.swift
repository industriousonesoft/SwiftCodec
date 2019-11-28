//
//  Encoder.swift
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

import Foundation
import CFFmpeg
import OCBridge

let AV_PIX_FMT_RGB32 = AVPixelFormat(OCBridgingHelper.avPixelFormatRGB32())

public class FFmpegEncoder: NSObject {
    
    private var inWidth: Int32 = 0
    private var inHeight: Int32 = 0
    private var outWidth: Int32 = 0
    private var outHeight: Int32 = 0
    
    private var codec: UnsafeMutablePointer<AVCodec>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    
    private var inFrame: UnsafeMutablePointer<AVFrame>?
    private var inFrameBuffer: UnsafeMutablePointer<UInt8>?
    
    private var outFrame: UnsafeMutablePointer<AVFrame>?
    private var outFrameBuffer: UnsafeMutablePointer<UInt8>?

    private var packet = AVPacket.init()
    private var swsContext: OpaquePointer?
    
    public override init() {
        super.init()
    }
    
    deinit {
        self.destotyEncoder()
    }
    
    public func initEncoder(inWidth: Int32, inHeight: Int32, outWidth: Int32, outHeight: Int32, bitrate: Int64) -> Bool {
        
        var hasError = false
        
        defer {
            if hasError == true {
                self.destotyEncoder()
            }
        }
        
        self.inWidth = inWidth
        self.inHeight = inHeight
        self.outWidth = outWidth
        self.outHeight = outHeight
        
        //Deprecated, No neccessary any more!
//        avcodec_register_all()
        
        if let codec = avcodec_find_encoder(AV_CODEC_ID_MPEG1VIDEO) {
            self.codec = codec
        }else {
            print("Can not create codec...")
            hasError = true
            return false
        }
        
        if let context = avcodec_alloc_context3(self.codec) {
            context.pointee.dct_algo = FF_DCT_FASTINT
            context.pointee.bit_rate = bitrate
            context.pointee.width = outWidth
            context.pointee.height = outHeight
            context.pointee.time_base.num = 1
            context.pointee.time_base.den = 30
            context.pointee.gop_size = 30
            context.pointee.max_b_frames = 0
            context.pointee.pix_fmt = AV_PIX_FMT_YUV420P
            self.codecContext = context
        }else {
            print("Can not create codec context...")
            hasError = true
            return false
        }
        
        if let codec = self.codec, let context = self.codecContext, avcodec_open2(context, codec, nil) != 0 {
            print("Can not opne avcodec...")
            hasError = true
            return false
        }
        
        //InFrame
        if let frame = av_frame_alloc() {
            frame.pointee.format = AV_PIX_FMT_RGB32.rawValue
            frame.pointee.width = inWidth
            frame.pointee.height = inHeight
            frame.pointee.pts = 0
            
            let frameSize = av_image_get_buffer_size(AV_PIX_FMT_YUV420P, outWidth, outHeight, 1)
            if frameSize < 0 {
                print("Can not get the buffer size...")
                hasError = true
                return false
            }
            
            self.inFrameBuffer = unsafeBitCast(malloc(Int(frameSize)), to: UnsafeMutablePointer<UInt8>.self)
            
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), self.inFrameBuffer, AV_PIX_FMT_RGB32, inWidth, inHeight, 1) < 0 {
                print("Can not fill input frame...")
                hasError = true
                return false
            }
            
            self.inFrame = frame
            
        }else {
            print("Can not create input frame...")
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
                print("Can not get the buffer size...")
                hasError = true
                return false
            }
            
            self.outFrameBuffer = unsafeBitCast(malloc(Int(frameSize)), to: UnsafeMutablePointer<UInt8>.self)
            
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), self.outFrameBuffer, AV_PIX_FMT_YUV420P, outWidth, outHeight, 1) < 0 {
                print("Can not fill output frame...")
                hasError = true
                return false
            }
            
            self.outFrame = frame
            
        }else {
            print("Can not create output frame...")
            hasError = true
            return false
        }
    
        if let sws = sws_getContext(inWidth, inHeight, AV_PIX_FMT_RGB32, outWidth, outHeight, AV_PIX_FMT_YUV420P, SWS_BILINEAR, nil, nil, nil) {
             self.swsContext = sws
        }else {
            print("Can not create sws context...")
            hasError = true
            return false
        }
        
        return true
    }
    
    public func destotyEncoder() {
        if let context = self.codecContext {
            avcodec_close(context)
            av_free(context)
        }
        if let sws = self.swsContext {
            sws_freeContext(sws)
        }
        if let frame = self.outFrame {
            av_free(frame)
        }
        if let frameBuffer = self.outFrameBuffer {
            free(frameBuffer)
        }
    }
    
    public func encode(rgbPixels: UnsafeMutablePointer<UInt8>, onEncoded:(UnsafeMutablePointer<UInt8>, Int32)->Void, onFailure:(NSError?)->Void) {
      
//        let inDataArray = unsafeBitCast([rgbPixels], to: UnsafePointer<UnsafePointer<UInt8>?>?.self)
//        let inLineSizeArray = unsafeBitCast([self.inWidth * 4], to: UnsafePointer<Int32>.self)

        if self.outFrame != nil && self.inFrame != nil {
            
            self.inFrame!.pointee.data.0 = rgbPixels
            //RGB32
            self.inFrame!.pointee.linesize.0 = self.inWidth * 4
            
            let sourceData = [
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.0),
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.1),
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.2),
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.3),
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.4),
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.5),
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.6),
                UnsafePointer<UInt8>(self.inFrame!.pointee.data.7),
            ]
            
            let sourceLineSize = [
                self.inFrame!.pointee.linesize.0,
                self.inFrame!.pointee.linesize.1,
                self.inFrame!.pointee.linesize.2,
                self.inFrame!.pointee.linesize.3,
                self.inFrame!.pointee.linesize.4,
                self.inFrame!.pointee.linesize.5,
                self.inFrame!.pointee.linesize.6,
                self.inFrame!.pointee.linesize.7
            ]
            
            let targetData = [
                self.outFrame!.pointee.data.0,
                self.outFrame!.pointee.data.1,
                self.outFrame!.pointee.data.2,
                self.outFrame!.pointee.data.3,
                self.outFrame!.pointee.data.4,
                self.outFrame!.pointee.data.5,
                self.outFrame!.pointee.data.6,
                self.outFrame!.pointee.data.7
            ]
            
            let targetLineSize = [
                self.outFrame!.pointee.linesize.0,
                self.outFrame!.pointee.linesize.1,
                self.outFrame!.pointee.linesize.2,
                self.outFrame!.pointee.linesize.3,
                self.outFrame!.pointee.linesize.4,
                self.outFrame!.pointee.linesize.5,
                self.outFrame!.pointee.linesize.6,
                self.outFrame!.pointee.linesize.7
            ]
            
            //Convert RGB32 to YUV420
            //Return the height of the output slice
            let destSliceH = sws_scale(self.swsContext, sourceData, sourceLineSize, 0, self.inHeight, targetData, targetLineSize)
            
            if destSliceH > 0 {
           
                //Why do pts here need to add 1?
                self.outFrame!.pointee.pts += 1
                
                av_init_packet(UnsafeMutablePointer<AVPacket>(&self.packet))
                
                defer {
                    av_packet_unref(UnsafeMutablePointer<AVPacket>(&self.packet))
                }
                
                var ret = avcodec_send_frame(self.codecContext, self.outFrame)
                if ret < 0 {
                    onFailure(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error about sending a packet for encoding."]))
                    return
                }
                
                ret = avcodec_receive_packet(self.codecContext, UnsafeMutablePointer<AVPacket>(&self.packet))
                if ret == OCBridgingHelper.avErrorEOF() {
                    print("avcodec_recieve_packet() encoder flushed...")
                }else if ret == OCBridgingHelper.avErrorEagain() {
                    print("avcodec_recieve_packet() need more input...")
                }else if ret < 0 {
                    onFailure(NSError.init(domain: "FFmpegEncoder", code: Int(ret), userInfo: [NSLocalizedDescriptionKey : "Error occured when encoding."]))
                    return
                }
                
                if ret == 0 {
                    
                    print("Encoded successfully...")
                
                    let packetSize = self.packet.size
                    let encodedData = unsafeBitCast(malloc(Int(packetSize)), to: UnsafeMutablePointer<UInt8>.self)
                    memcpy(encodedData, self.packet.data, Int(packetSize))
                    
                    onEncoded(encodedData, packetSize)
                  
                }
            }
           
        }else {
            onFailure(NSError.init(domain: "FFmpegEncoder", code: Int(-1), userInfo: [NSLocalizedDescriptionKey : "Encoder not initailized."]))
        }
        
    }
    
}
