//
//  Codec.FFmpeg.Decoder.Audio.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/28.
//  Copyright © 2020 zenet. All rights reserved.
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
    
    func open(config: Codec.FFmpeg.Decoder.AudioConfig) throws {
        try self.base.open(config: config)
    }
    
    func close() {
        self.base.closeAudioSession()
    }
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedAudioCallback) {
        self.base.decode(bytes: bytes, size: size, timestamp: timestamp, onDecoded: onDecoded)
    }
}

//MARK: - Decode Audio
extension Codec.FFmpeg.Decoder {
    
    func open(config: AudioConfig) throws {
        self.audioSession = try AudioSession.init(config: config)
    }
    
    func closeAudioSession() {
        self.audioSession = nil
    }
    
    func decode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, timestamp: UInt64, onDecoded: Codec.FFmpeg.Decoder.DecodedAudioCallback) {
        self.audioSession?.decode(bytes: bytes, size: size, timestamp: timestamp, onDecoded: onDecoded)
    }
}
