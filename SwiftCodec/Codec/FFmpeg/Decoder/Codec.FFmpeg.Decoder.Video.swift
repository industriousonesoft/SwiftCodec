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
    
    var video: Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Decoder> {
        return Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Decoder>.init(self)
    }
    
    static var video: Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Decoder>.Type {
        return Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Decoder>.self
    }
}

public
extension Codec.FFmpeg.VideoCompatible where Base: Codec.FFmpeg.Decoder {

    func open(format: Codec.FFmpeg.Decoder.Video.Format) throws {
        try self.base.open(format: format)
    }
    
    func close() {
        self.base.closeVideoSession()
    }
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, isKeyFrame: Bool, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedVideoCallback) {
        self.base.decode(bytes: bytes, size: size, isKeyFrame: isKeyFrame, timestamp: timestamp, onDecoded: onDecoded)
    }
}

//MARK: - Decode Audio
extension Codec.FFmpeg.Decoder {
    
    func open(format: Video.Format) throws {
        self.videoSession = try Video.Session.init(format: format)
    }
    
    func closeVideoSession() {
        self.videoSession = nil
    }
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, isKeyFrame: Bool, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedVideoCallback) {
        self.videoSession?.decode(bytes: bytes, size: size, isKeyFrame: isKeyFrame, timestamp: timestamp, onDecoded: onDecoded)
    }
}
