//
//  Codec.FFmpeg.Decoder.Audio.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/28.
//  Copyright © 2020 industriousonesoft. All rights reserved.
//

import Foundation

public
extension Codec.FFmpeg.Decoder {
    
    var audio: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder> {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.init(self)
    }
    
    static var audio: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.Type {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.self
    }
}

public
extension Codec.FFmpeg.AudioCompatible where Base: Codec.FFmpeg.Decoder {
    
    func open(format: Codec.FFmpeg.Decoder.Audio.Format) throws {
        try self.base.open(format: format)
    }
    
    func close() {
        self.base.closeAudioSession()
    }
    
    func decode(bytes: UnsafePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedAudioCallback) {
        self.base.decode(bytes: bytes, size: size, timestamp: timestamp, onDecoded: onDecoded)
    }
}

//MARK: - Decode Audio
extension Codec.FFmpeg.Decoder {
    
    func open(format: Audio.Format) throws {
        self.audioSession = try Audio.Session.init(format: format)
    }
    
    func closeAudioSession() {
        self.audioSession = nil
    }
    
    func decode(bytes: UnsafePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedAudioCallback) {
        self.audioSession?.decode(bytes: bytes, size: size, timestamp: timestamp, onDecoded: onDecoded)
    }
}
