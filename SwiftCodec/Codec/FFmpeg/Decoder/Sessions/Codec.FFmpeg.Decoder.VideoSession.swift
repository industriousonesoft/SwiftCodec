//
//  VideoSession.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/22.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

private let ErrorDomain = "FFmpeg:Video:Decoder"

extension Codec.FFmpeg.Decoder {
    
    class VideoSession {
        
        private var config: VideoConfig
    
        private var decodeQueue: DispatchQueue
    
        private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
        
        private var decodedFrame: UnsafeMutablePointer<AVFrame>?
        private var scaledFrame: UnsafeMutablePointer<AVFrame>?
        
        private var packet: UnsafeMutablePointer<AVPacket>?
        
        private var swsCtx: OpaquePointer?
        
        init(config: VideoConfig, decodeIn queue: DispatchQueue? = nil) throws {
            self.config = config
            self.decodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.VideoSession.decode.queue")
            try self.createCodecCtx(config: config)
            try self.createDecodedFrame(size: config.outSize)
            try self.createScaledFrame(size: config.outSize)
            try self.createPakcet()
            try self.createSwsCtx(inSize: config.outSize)
        }
        
        deinit {
            self.destroySwsCtx()
            self.destroyScaledFrame()
            self.destroyDecodedFrame()
            self.destroyPacket()
            self.destroyCodecCtx()
        }
    }
}

//MARK: - Codec Context
private
extension Codec.FFmpeg.Decoder.VideoSession {
    
    func createCodecCtx(config: Codec.FFmpeg.Decoder.VideoConfig) throws {
        
        let codecId: AVCodecID = config.codec.avCodecID
        let codec = avcodec_find_decoder(codecId)
        
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Failed to create video decode context.")!
        }
        
        codecCtx.pointee.codec_id = codecId
        codecCtx.pointee.codec_type = AVMEDIA_TYPE_VIDEO
        codecCtx.pointee.bit_rate = config.bitRate
        codecCtx.pointee.width = Int32(config.outSize.width)
        codecCtx.pointee.height = Int32(config.outSize.height)
        codecCtx.pointee.time_base = AVRational.init(num: 1, den: config.fps)
        codecCtx.pointee.pix_fmt = config.srcPixelFmt.avPixelFormat
        
        guard avcodec_open2(codecCtx, codec, nil) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to open video deconder.")!
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
extension Codec.FFmpeg.Decoder.VideoSession {

    func createDecodedFrame(size: CGSize) throws {
        self.decodedFrame = try self.createFrame(pixFmt: self.config.srcPixelFmt.avPixelFormat, size: size, fillIfNecessary: false)
    }
    
    func destroyDecodedFrame() {
        if self.decodedFrame != nil {
            av_frame_free(&self.decodedFrame)
            self.decodedFrame = nil
        }
    }
    
    func createScaledFrame(size: CGSize) throws {
        self.scaledFrame = try self.createFrame(pixFmt: self.config.dstPixelFmt.avPixelFormat, size: size, fillIfNecessary: true)
    }
    
    func destroyScaledFrame() {
        if self.scaledFrame != nil {
            av_frame_free(&self.scaledFrame)
            self.scaledFrame = nil
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
            let bufferSize = av_image_get_buffer_size(pixFmt, Int32(size.width), Int32(size.height), 1)
            if bufferSize < 0 {
                throw NSError.error(ErrorDomain, reason: "Can not get the video output frame buffer size.")!
            }
            
            let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferSize))
            if av_image_fill_arrays(&(frame.pointee.data.0), &(frame.pointee.linesize.0), buff, pixFmt, Int32(size.width), Int32(size.height), 1) < 0 {
                throw NSError.error(ErrorDomain, reason: "Faild to initialize out frame buffer.")!
            }
        }
        return frame
    }
}

//MARK: - AVPacket
private
extension Codec.FFmpeg.Decoder.VideoSession {
    
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

//MARK: - Sws Context
private
extension Codec.FFmpeg.Decoder.VideoSession {

    func createSwsCtx(inSize: CGSize) throws {
        if let sws = sws_getContext(Int32(inSize.width), Int32(inSize.height), self.config.srcPixelFmt.avPixelFormat, Int32(self.config.outSize.width), Int32(self.config.outSize.height), self.config.dstPixelFmt.avPixelFormat, SWS_FAST_BILINEAR, nil, nil, nil) {
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

//MARK: - Decode
extension Codec.FFmpeg.Decoder.VideoSession {

    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedVideoCallback) {
        
        guard let codecCtx = self.codecCtx,
            let packet = self.packet,
            let decodedFrame = self.decodedFrame,
            let scaledFrame = self.scaledFrame,
            let swsCtx = self.swsCtx else {
                onDecoded(nil, NSError.error(ErrorDomain, reason: "Video decoder not initialized yet.")!)
                return
        }
        
        av_init_packet(packet)
        packet.pointee.data = bytes
        packet.pointee.size = size
        
        var ret = avcodec_send_packet(codecCtx, packet)
        
        if ret < 0 {
            onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when sending video packet for decoding.")!)
            return
        }
        
        ret = avcodec_receive_frame(codecCtx, decodedFrame)
        
        if ret == 0 {
            
            if self.config.srcPixelFmt != self.config.dstPixelFmt {
                
                let dstSliceH = sws_scale(swsCtx, decodedFrame.pointee.sliceArray, decodedFrame.pointee.strideArray, 0, Int32(codecCtx.pointee.height), scaledFrame.pointee.mutablleSliceArray, scaledFrame.pointee.strideArray)
                
                guard dstSliceH > 0 else {
                    onDecoded(nil, NSError.error(ErrorDomain, reason: "Failed to scale \(self.config.srcPixelFmt) to \(self.config.dstPixelFmt)."))
                    return
                }
                
                do {
                    let data = try self.dump(from: scaledFrame, codecCtx: codecCtx)
                    onDecoded(data, nil)
                } catch let err {
                    onDecoded(nil, err)
                }
                
            }else {
                do {
                    let data = try self.dump(from: decodedFrame, codecCtx: codecCtx)
                    onDecoded(data, nil)
                } catch let err {
                    onDecoded(nil, err)
                }
            }
            
//            print("\(#function) decoded frame: \(decodedFrame.pointee.pts)")
            
        }else {
            if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EOF {
                print("[Video] avcodec_receive_frame() encoder flushed...")
            }else if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EAGAIN {
                print("[Video] avcodec_receive_frame() need more input...")
            }else if ret < 0 {
                onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when receiving video frame.")!)
            }
        }
        
        av_frame_unref(decodedFrame)
        
    }
    
}

//MARK: - Decode
extension Codec.FFmpeg.Decoder.VideoSession {
    
    func dump(from frame: UnsafePointer<AVFrame>, codecCtx: UnsafePointer<AVCodecContext>) throws -> Data {
        
        if self.config.dstPixelFmt == .YUV420P {
            if let data = self.dumpYUV420Data(from: frame, codecCtx: codecCtx) {
                return data
            }else {
                throw NSError.error(ErrorDomain, reason: "Failed to dump yuv raw data from avframe.")!
            }
        }else if self.config.dstPixelFmt == .RGB32 {
            
            if let bytesTuple = self.dumpRGBBytes(from: frame, codecCtx: codecCtx) {
                //onDecoded(bytesTuple, nil)
                return Data.init(bytes: bytesTuple.bytes, count: bytesTuple.size)
            }else {
                throw NSError.error(ErrorDomain, reason: "Failed to dump rgb raw data from avframe.")!
            }
            
        }else {
            throw NSError.error(ErrorDomain, reason: "Unsuppored pixel format to dump: \(self.config.dstPixelFmt)")!
        }
    }
    
    func dumpYUV420Data(from frame: UnsafePointer<AVFrame>, codecCtx: UnsafePointer<AVCodecContext>) -> Data? {
        
        if let bytesY = frame.pointee.data.0,
         let bytesU = frame.pointee.data.1,
         let bytesV = frame.pointee.data.2 {
            
            let sizeY = Int(codecCtx.pointee.width * codecCtx.pointee.height)
         
            var yuvData = Data.init(bytes: bytesY, count: sizeY)
            yuvData.append(bytesU, count: sizeY / 4)
            yuvData.append(bytesV, count: sizeY / 4)
            
            return yuvData
        }
        return nil
    }
    
    func dumpYUV420Bytes(from frame: UnsafePointer<AVFrame>, codecCtx: UnsafePointer<AVCodecContext>) -> (bytes: UnsafeMutablePointer<UInt8>, size: Int)? {
        
        if let bytesY = frame.pointee.data.0,
            let bytesU = frame.pointee.data.1,
            let bytesV = frame.pointee.data.2 {
            
            let width = Int(codecCtx.pointee.width)
            let height = Int(codecCtx.pointee.height)
            let sizeY = width * height
             
            let yuvBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: sizeY + sizeY / 2)
            
            for i in 0..<height {
                memcpy(yuvBytes + width * i, bytesY + Int(frame.pointee.linesize.0) * i, width)
            }
            
            for i in 0..<height/2 {
                memcpy(yuvBytes + sizeY + width / 2 * i, bytesU + Int(frame.pointee.linesize.1) * i, width / 2)
            }
            
            for i in 0..<height/2 {
                memcpy(yuvBytes + sizeY + sizeY / 4 + width / 2 * i, bytesV + Int(frame.pointee.linesize.2) * i, width / 2)
            }
            
            return (bytes: yuvBytes, size: sizeY + sizeY / 2)
        }else {
            return nil
        }
    }
    
    func dumpRGBBytes(from frame: UnsafePointer<AVFrame>, codecCtx: UnsafePointer<AVCodecContext>) -> (bytes: UnsafeMutablePointer<UInt8>, size: Int)? {
        
        if let bytes = frame.pointee.data.0 {
            
            let size = Int(frame.pointee.linesize.0)
            let rgbBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            memcpy(rgbBytes, bytes, size)
            
            return (bytes: rgbBytes, size: size)
        }else {
            return nil
        }
        
    }
    
}
