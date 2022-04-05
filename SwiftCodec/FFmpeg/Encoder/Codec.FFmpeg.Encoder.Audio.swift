//
//  Codec.FFmpeg.Encoder.Audio.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 industriousonesoft. All rights reserved.
//

import Foundation
import CFFmpeg

public
extension Codec.FFmpeg.Encoder {
    
    var audio: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Encoder> {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Encoder>.init(self)
    }
    
    static var audio: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Encoder>.Type {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Encoder>.self
    }
}

public
extension Codec.FFmpeg.AudioCompatible where Base: Codec.FFmpeg.Encoder {
    
    func open(format: Codec.FFmpeg.Encoder.Audio.Format, queue: DispatchQueue? = nil) throws {
        try self.base.open(format: format, queue: queue)
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
    
    func open(format: Audio.Format, queue: DispatchQueue? = nil) throws {
        self.audioSession = try Audio.Session.init(format: format, queue: queue)
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
