//
//  MuxSession.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

private let ErrorDomain = "FFmpeg:Muxer"

extension Codec.FFmpeg.Encoder {
    
    typealias MuxFormat = String
    
    class MuxSession: NSObject {
        internal var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        
        internal var videoStream: UnsafeMutablePointer<AVStream>?
        internal var audioStream: UnsafeMutablePointer<AVStream>?
    }
}

extension Codec.FFmpeg.Encoder.MuxFormat {
    static let mpegts = "mpegts"
}

extension Codec.FFmpeg.Encoder.MuxSession {
    
    func open(format: Codec.FFmpeg.Encoder.MuxFormat) throws {
        
        guard avformat_alloc_output_context2(&self.fmtCtx, nil, format, nil) >= 0  else {
            throw NSError.error(ErrorDomain, reason: "Failed to create output context.")!
        }
        weak var weakSelf = self
        withUnsafeMutablePointer(to: &weakSelf) { [unowned self] (ptr) in
            let ioBufferSize: Int = 512*1024 //32768
            let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: ioBufferSize)
            let writable: Int = 1
            let ioCtx = avio_alloc_context(buff, Int32(ioBufferSize), Int32(writable), ptr, nil, muxerCallback, nil)
            self.fmtCtx?.pointee.pb = ioCtx
            self.fmtCtx?.pointee.flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_NOFILE | AVFMT_FLAG_FLUSH_PACKETS
        }
    }
    
    func add(video session: Codec.FFmpeg.Encoder.VideoSession) throws {
        guard let codecCtx = session.codecCtx else {
            throw NSError.error(ErrorDomain, reason: "Video codec context not created yet.")!
        }
        self.videoStream = try self.addStream(codecCtx: codecCtx)
    }
    
    func add(audio session: Codec.FFmpeg.Encoder.VideoSession) throws {
        guard let codecCtx = session.codecCtx else {
            throw NSError.error(ErrorDomain, reason: "Video codec context not created yet.")!
        }
        self.audioStream = try self.addStream(codecCtx: codecCtx)
    }
   
    
}

private
extension Codec.FFmpeg.Encoder.MuxSession {
    
    func addStream(codecCtx: UnsafeMutablePointer<AVCodecContext>) throws -> UnsafeMutablePointer<AVStream> {
        
        guard let fmtCtx = self.fmtCtx else {
            throw NSError.error(ErrorDomain, reason: "Output context not created yet.")!
        }
        
        guard let stream = avformat_new_stream(self.fmtCtx, codecCtx.pointee.codec) else {
            throw NSError.error(ErrorDomain, reason: "Failed to create video staream.")!
        }
        
        guard avcodec_parameters_from_context(stream.pointee.codecpar, codecCtx) >= 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to initialize video staream.")!
        }
        
        stream.pointee.id = Int32(fmtCtx.pointee.nb_streams - 1)
        
        return stream
    }
    
    func addHeader() throws {
        guard let fmtCtx = self.fmtCtx else {
            throw NSError.error(ErrorDomain, reason: "Output context not created yet.")!
        }
        
        guard avformat_write_header(fmtCtx, nil) >= 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to write output header.")!
        }
    }
    
    func addTrailer() throws {
        guard let fmtCtx = self.fmtCtx else {
            throw NSError.error(ErrorDomain, reason: "Output context not created yet.")!
        }
        
        guard av_write_trailer(fmtCtx) >= 0 else {
            throw NSError.error(ErrorDomain, reason: "Failed to write output trailer.")!
        }
    }
}

private
func muxerCallback(opaque: UnsafeMutableRawPointer?, buff: UnsafeMutablePointer<UInt8>?, buffSize :Int32) -> Int32 {
       
    if buff != nil && buffSize > 0 {
        if opaque != nil {
            let encodedData = unsafeBitCast(malloc(Int(buffSize)), to: UnsafeMutablePointer<UInt8>.self)
            memcpy(encodedData, buff, Int(buffSize))
            let session = unsafeBitCast(opaque, to: Codec.FFmpeg.Encoder.MuxSession.self)
            
        }
    }
    
    return 0
}



