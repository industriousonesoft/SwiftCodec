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
    
    func open(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        try self.base.open(in: desc, config: config)
    }
    
    func encode(pcm buffer: UnsafeMutablePointer<UInt8>, len: Int32) throws {
        try self.base.encode(pcm: buffer, len: len)
    }
    
}

//MARK: Audio
private
extension Codec.FFmpeg.Encoder {
    
    func open(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        try self.audioSession.open(in: desc, config: config)
    }
    
    func encode(pcm buffer: UnsafeMutablePointer<UInt8>, len: Int32) throws {
        try self.audioSession.encode(pcm: buffer, len: len)
    }
}
