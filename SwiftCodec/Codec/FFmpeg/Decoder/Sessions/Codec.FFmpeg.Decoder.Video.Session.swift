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

extension Codec.FFmpeg.Decoder.Video {
    
    class Session {
        private var format: Format
    
        private var decodeQueue: DispatchQueue
    
        private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
        private var parserCtx: UnsafeMutablePointer<AVCodecParserContext>?
        
        private var decodedFrame: UnsafeMutablePointer<AVFrame>?
        private var scaledFrame: UnsafeMutablePointer<AVFrame>?
        
        private var packet: UnsafeMutablePointer<AVPacket>?
        
        private var swsCtx: OpaquePointer?
        
        init(format: Format, decodeIn queue: DispatchQueue? = nil) throws {
            self.format = format
            self.decodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.VideoSession.decode.queue")
            try self.createCodecCtx(format: format)
//            try self.createParser(codecId: config.codec.avCodecID)
            try self.createDecodedFrame(size: format.outSize)
            try self.createScaledFrame(size: format.outSize)
            try self.createPakcet()
            try self.createSwsCtx(inSize: format.outSize)
        }
        
        deinit {
            self.destroySwsCtx()
            self.destroyScaledFrame()
            self.destroyDecodedFrame()
            self.destroyPacket()
//            self.destroyParser()
            self.destroyCodecCtx()
        }
    }
}

//MARK: - Codec Context
private
extension Codec.FFmpeg.Decoder.Video.Session {
    
    func createCodecCtx(format: Codec.FFmpeg.Decoder.Video.Format) throws {
        
        let codecId: AVCodecID = format.codec.avCodecID
        let codec = avcodec_find_decoder(codecId)
        
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Failed to create video decode context.")!
        }
        
        codecCtx.pointee.codec_id = codecId
        codecCtx.pointee.codec_type = AVMEDIA_TYPE_VIDEO
        codecCtx.pointee.bit_rate = format.bitRate
        codecCtx.pointee.width = Int32(format.outSize.width)
        codecCtx.pointee.height = Int32(format.outSize.height)
        codecCtx.pointee.time_base = AVRational.init(num: 1, den: format.fps)
        codecCtx.pointee.pix_fmt = format.srcPixelFmt.avPixelFormat
        
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
extension Codec.FFmpeg.Decoder.Video.Session {

    func createDecodedFrame(size: CGSize) throws {
        self.decodedFrame = try self.createFrame(pixFmt: self.format.srcPixelFmt.avPixelFormat, size: size, fillIfNecessary: false)
    }
    
    func destroyDecodedFrame() {
        if self.decodedFrame != nil {
            av_frame_free(&self.decodedFrame)
            self.decodedFrame = nil
        }
    }
    
    func createScaledFrame(size: CGSize) throws {
        self.scaledFrame = try self.createFrame(pixFmt: self.format.dstPixelFmt.avPixelFormat, size: size, fillIfNecessary: true)
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

//MARK: - Parser Context
private
extension Codec.FFmpeg.Decoder.Video.Session {
    
    func createParser(codecId: AVCodecID) throws {
        guard let parser = av_parser_init(Int32(codecId.rawValue)) else {
            throw NSError.error(ErrorDomain, reason: "Failed to create parser context.")!
        }
        self.parserCtx = parser
    }
    
    func destroyParser() {
        if self.parserCtx != nil {
            av_parser_close(self.parserCtx!)
            self.parserCtx = nil
        }
    }
}

//MARK: - AVPacket
private
extension Codec.FFmpeg.Decoder.Video.Session {
    
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
extension Codec.FFmpeg.Decoder.Video.Session {

    func createSwsCtx(inSize: CGSize) throws {
        if let sws = sws_getContext(Int32(inSize.width), Int32(inSize.height), self.format.srcPixelFmt.avPixelFormat, Int32(self.format.outSize.width), Int32(self.format.outSize.height), self.format.dstPixelFmt.avPixelFormat, SWS_FAST_BILINEAR, nil, nil, nil) {
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
extension Codec.FFmpeg.Decoder.Video.Session {

    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, isKeyFrame: Bool, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedVideoCallback) {
        
        guard let codecCtx = self.codecCtx,
            /*let parserCtx = self.parserCtx,*/
            let packet = self.packet,
            let decodedFrame = self.decodedFrame,
            let scaledFrame = self.scaledFrame,
            let swsCtx = self.swsCtx else {
                onDecoded(nil, NSError.error(ErrorDomain, reason: "Video decoder not initialized yet.")!)
                return
        }
        
        //FIXME: 使用这种方式掉帧情况很严重，原因暂时不明
        /*
        var ret = av_parser_parse2(parserCtx, codecCtx, &packet.pointee.data, &packet.pointee.size, bytes, size, Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE, Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE, 0)
        
        if ret < 0 {
            onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when parsering video packet for decoding.")!)
            return
        }
        print("Parser Packet Size: \(packet.pointee.size)")
        guard packet.pointee.size > 0 else {
            return
        }
         */
        
        av_init_packet(packet)
        packet.pointee.data = bytes
        packet.pointee.size = size
        packet.pointee.pos = 0
        packet.pointee.pts = Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE
        packet.pointee.dts = Codec.FFmpeg.SWIFT_AV_NOPTS_VALUE
        
        if isKeyFrame {
            packet.pointee.flags |= AV_PKT_FLAG_KEY
        }
        
        var ret = avcodec_send_packet(codecCtx, packet)
        
        if ret < 0 {
            onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when sending video packet for decoding.")!)
            return
        }
        
        ret = avcodec_receive_frame(codecCtx, decodedFrame)
        
        if ret == 0 {
            
            if self.format.srcPixelFmt != self.format.dstPixelFmt {
                
                let dstSliceH = sws_scale(swsCtx, decodedFrame.pointee.sliceArray, decodedFrame.pointee.strideArray, 0, Int32(codecCtx.pointee.height), scaledFrame.pointee.mutablleSliceArray, scaledFrame.pointee.strideArray)
                
                guard dstSliceH > 0 else {
                    onDecoded(nil, NSError.error(ErrorDomain, reason: "Failed to scale \(self.format.srcPixelFmt) to \(self.format.dstPixelFmt)."))
                    return
                }
                
                do {
//                    let tuple = try self.dumpBytes(from: scaledFrame, codecCtx: codecCtx)
//                    onDecoded(tuple, nil)
                    let data = try self.dumpData(from: scaledFrame, codecCtx: codecCtx)
                    onDecoded(data, nil)
                } catch let err {
                    onDecoded(nil, err)
                }
                
            }else {
                do {
//                    let tuple = try self.dumpBytes(from: decodedFrame, codecCtx: codecCtx)
//                    onDecoded(tuple, nil)
                    let data = try self.dumpData(from: decodedFrame, codecCtx: codecCtx)
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
extension Codec.FFmpeg.Decoder.Video.Session {
    
    func dumpData(from frame: UnsafePointer<AVFrame>, codecCtx: UnsafePointer<AVCodecContext>) throws -> Data {
        
        if self.format.dstPixelFmt == .YUV420P {
            if let data = self.dumpYUV420Data(from: frame, codecCtx: codecCtx) {
                return data
            }else {
                throw NSError.error(ErrorDomain, reason: "Failed to dump yuv raw data from avframe.")!
            }
        }else if self.format.dstPixelFmt == .RGB32 {
            
            if let bytesTuple = self.dumpRGBBytes(from: frame, codecCtx: codecCtx) {
                //onDecoded(bytesTuple, nil)
                return Data.init(bytes: bytesTuple.bytes, count: bytesTuple.size)
            }else {
                throw NSError.error(ErrorDomain, reason: "Failed to dump rgb raw data from avframe.")!
            }
            
        }else {
            throw NSError.error(ErrorDomain, reason: "Unsuppored pixel format to dump: \(self.format.dstPixelFmt)")!
        }
    }
    
    func dumpBytes(from frame: UnsafePointer<AVFrame>, codecCtx: UnsafePointer<AVCodecContext>) throws -> (bytes: UnsafeMutablePointer<UInt8>, size: Int)? {
        
        if self.format.dstPixelFmt == .YUV420P {
            if let tuple = self.dumpYUV420Bytes(from: frame, codecCtx: codecCtx) {
                return tuple
            }else {
                throw NSError.error(ErrorDomain, reason: "Failed to dump yuv raw data from avframe.")!
            }
        }else if self.format.dstPixelFmt == .RGB32 {
            
            if let tuple = self.dumpRGBBytes(from: frame, codecCtx: codecCtx) {
                //onDecoded(bytesTuple, nil)
                return tuple
            }else {
                throw NSError.error(ErrorDomain, reason: "Failed to dump rgb raw data from avframe.")!
            }
            
        }else {
            throw NSError.error(ErrorDomain, reason: "Unsuppored pixel format to dump: \(self.format.dstPixelFmt)")!
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
