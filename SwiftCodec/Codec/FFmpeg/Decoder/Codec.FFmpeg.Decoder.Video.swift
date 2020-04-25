//
//  Codec.FFmpeg.Decoder.Video.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/25.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

public
extension Codec.FFmpeg.Decoder {
    
    var video: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder> {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.init(self)
    }
    
    static var video: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.Type {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.self
    }
}

public
extension Codec.FFmpeg.AudioCompatible where Base: Codec.FFmpeg.Decoder {

    func open(config: Codec.FFmpeg.Video.Config) throws {
        try self.base.open(config: config)
    }
    
    func close() {
        self.base.closeVideoSession()
    }
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedDataCallback) {
        self.base.decode(bytes: bytes, size: size, timestamp: timestamp, onDecoded: onDecoded)
    }
}

extension Codec.FFmpeg.Decoder {
    
    func open(config: Codec.FFmpeg.Video.Config) throws {
        self.videoSession = try VideoSession.init(config: config)
    }
    
    func closeVideoSession() {
        self.videoSession = nil
    }
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedDataCallback) {
        self.videoSession?.decode(bytes: bytes, size: size, timestamp: timestamp, onDecoded: onDecoded)
    }
}
