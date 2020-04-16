//
//  Codec.FFmpeg.Encoder.Audio.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

//MARK: - AudioCompatible
public struct AudioCompatible<Base> {
    let base: Base
    init(_ base: Base) {
        self.base = base
    }
}

public
extension Codec.FFmpeg.Encoder {
    
    var audio: AudioCompatible<Codec.FFmpeg.Encoder> {
        return AudioCompatible<Codec.FFmpeg.Encoder>.init(self)
    }
    
    static var audio: AudioCompatible<Codec.FFmpeg.Encoder>.Type {
        return AudioCompatible<Codec.FFmpeg.Encoder>.self
    }
}

public
extension AudioCompatible where Base: Codec.FFmpeg.Encoder {
    
    func open(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config, queue: DispatchQueue? = nil) throws {
        try self.base.open(in: desc, config: config, queue: queue)
    }
    
    func close() {
        self.base.closeAudioSession()
    }
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedDataCallback) {
        self.base.encode(bytes: bytes, size: size, onEncoded: onEncoded)
    }
    
}

//MARK: Audio
private
extension Codec.FFmpeg.Encoder {
    
    func open(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config, queue: DispatchQueue? = nil) throws {
        self.audioSession = try AudioSession.init(in: desc, config: config, queue: queue)
    }
    
    func closeAudioSession() {
        self.audioSession = nil
    }
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: Int32, onEncoded: @escaping EncodedDataCallback) {
        self.audioSession?.encode(bytes: bytes, size: size, onEncoded: { (packet, error) in
            if packet != nil {
                let size = Int(packet!.pointee.size)
                let encodedBytes = unsafeBitCast(malloc(size), to: UnsafeMutablePointer<UInt8>.self)
                memcpy(encodedBytes, packet!.pointee.data, size)
                onEncoded((encodedBytes, Int32(size)), nil)
                av_packet_unref(packet!)
            }else {
                onEncoded(nil, error)
            }
        })
        
    }
}
