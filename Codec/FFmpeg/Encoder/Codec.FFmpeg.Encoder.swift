//
//  Codec.FFmpeg.Encoder.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

extension Codec.FFmpeg {
    
    public class Encoder: NSObject {
        
        private lazy var audioSession = {
            return AudioSession.init()
        }()
    }
    
}
//MARK: - AudioCompatible
public struct AudioCompatible<Base> {
    let base: Base
    init(_ base: Base) {
        self.base = base
    }
}

public extension AudioCompatible where Base: Codec.FFmpeg.Encoder {
    
    func open(in desc: Codec.FFmpeg.AudioDescription, config: Codec.FFmpeg.Config) throws {
        try self.base.open(in: desc, config: config)
    }
    
    func close() {
        self.base.close()
    }
    
    func encode(pcm buffer: UnsafeMutablePointer<UInt8>, len: Int32) throws {
        try self.base.encode(pcm: buffer, len: len)
    }
    
}

//MARK: Audio
public
extension Codec.FFmpeg.Encoder {
    
    var audio: AudioCompatible<Codec.FFmpeg.Encoder> {
        return AudioCompatible<Codec.FFmpeg.Encoder>.init(self)
    }
    
    static var audio: AudioCompatible<Codec.FFmpeg.Encoder>.Type {
        return AudioCompatible<Codec.FFmpeg.Encoder>.self
    }
}

private
extension Codec.FFmpeg.Encoder {
    
    func open(in desc: Codec.FFmpeg.AudioDescription, config: Codec.FFmpeg.Config) throws {
        try self.audioSession.open(in: desc, config: config)
    }
    
    func close() {
        self.audioSession.close()
    }
    
    func encode(pcm buffer: UnsafeMutablePointer<UInt8>, len: Int32) throws {
        try self.audioSession.encode(pcm: buffer, len: len)
    }
}
