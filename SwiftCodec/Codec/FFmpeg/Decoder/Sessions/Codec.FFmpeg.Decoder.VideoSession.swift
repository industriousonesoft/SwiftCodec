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
    
        private var decodeQueue: DispatchQueue
    
        private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
        
        private var decodedFrame: UnsafeMutablePointer<AVFrame>?
        private var scaledFrame: UnsafeMutablePointer<AVFrame>?
        
        private var packet: UnsafeMutablePointer<AVPacket>?
        
        private var swsCtx: OpaquePointer?
        
        init(config: Codec.FFmpeg.Video.Config, decodeIn queue: DispatchQueue? = nil) throws {
            self.decodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.VideoSession.decode.queue")
            try self.createCodec(config: config)
            try self.createDecodedFrame(size: config.outSize)
            try self.createScaledFrame(size: config.outSize)
            try self.createPakcet()
        }
        
        deinit {
            self.destroySwsCtx()
            self.destroyScaledFrame()
            self.destroyDecodedFrame()
            self.destroyCodecCtx()
        }
    }
}

//MARK: - Codec Context
private
extension Codec.FFmpeg.Decoder.VideoSession {
    
    func createCodec(config: Codec.FFmpeg.Video.Config) throws {
        
        let codecId: AVCodecID = config.codec.codecID()
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
        codecCtx.pointee.pix_fmt = config.codec.pixelFormat()
        
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

private
extension Codec.FFmpeg.Decoder.VideoSession {

    func createDecodedFrame(size: CGSize) throws {
        self.decodedFrame = try self.createFrame(pixFmt: AV_PIX_FMT_YUV420P, size: size, fillIfNecessary: false)
    }
    
    func destroyDecodedFrame() {
        if self.decodedFrame != nil {
            av_frame_free(&self.decodedFrame)
            self.decodedFrame = nil
        }
    }
    
    func createScaledFrame(size: CGSize) throws {
        self.scaledFrame = try self.createFrame(pixFmt: Codec.FFmpeg.SWIFT_AV_PIX_FMT_RGB32, size: size, fillIfNecessary: true)
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

    func createSwsCtx(inSize: CGSize, outSize: CGSize) throws {
        if let sws = sws_getContext(Int32(inSize.width), Int32(inSize.height), AV_PIX_FMT_YUV420P, Int32(outSize.width), Int32(outSize.height), Codec.FFmpeg.SWIFT_AV_PIX_FMT_RGB32, SWS_FAST_BILINEAR, nil, nil, nil) {
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

    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedDataCallback) {
        
        guard let codecCtx = self.codecCtx,
            let packet = self.packet,
            let decodedFrame = self.decodedFrame,
            let scaledFrame = self.scaledFrame,
            let swsCtx = self.swsCtx else {
            return
        }
        
        av_init_packet(packet)
        packet.pointee.data = bytes
        packet.pointee.size = size
        
        var ret = avcodec_send_packet(codecCtx, packet)
        
        if ret < 0 {
            onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when encoding video.")!)
            return
        }
        
        ret = avcodec_receive_frame(codecCtx, decodedFrame)
        
        if ret == 0 {
            let dstSliceH = sws_scale(swsCtx, decodedFrame.pointee.sliceArray, decodedFrame.pointee.strideArray, 0, Int32(codecCtx.pointee.height), scaledFrame.pointee.mutablleSliceArray, scaledFrame.pointee.strideArray)
            if dstSliceH > 0 {
                //RGB格式其数据格式是存储在单个数组中：
                if let bytes = scaledFrame.pointee.data.0 {
                    onDecoded((bytes: bytes, size: scaledFrame.pointee.linesize.0), nil)
                }
                /*YUV420格式，则：
                    yuvSize = codecCtx.pointee.width * codecCtx.pointee.height
                    Y: scaledFrame.pointee.data.0 - yuvSize
                    U: scaledFrame.pointee.data.1 - yuvSize / 4
                    V: scaledFrame.pointee.data.2 - yuvSize / 4
                    */
            }
        }else {
            if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EOF {
                print("avcodec_send_packet() encoder flushed...")
            }else if ret == Codec.FFmpeg.SWIFT_AV_ERROR_EAGAIN {
                print("avcodec_send_packet() need more input...")
            }else if ret < 0 {
                onDecoded(nil, NSError.error(ErrorDomain, code: Int(ret), reason: "Error occured when encoding video.")!)
            }
        }
        av_frame_unref(decodedFrame)
        
    }
    
}
