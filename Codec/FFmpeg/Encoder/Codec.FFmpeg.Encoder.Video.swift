//
//  Codec.FFmpeg.Encoder.Video.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

//MARK: - VideoCompatible
public struct VideoCompatible<Base> {
    let base: Base
    init(_ base: Base) {
        self.base = base
    }
}

public
extension Codec.FFmpeg.Encoder {
    
    var video: VideoCompatible<Codec.FFmpeg.Encoder> {
        return VideoCompatible<Codec.FFmpeg.Encoder>.init(self)
    }
    
    static var video: VideoCompatible<Codec.FFmpeg.Encoder>.Type {
        return VideoCompatible<Codec.FFmpeg.Encoder>.self
    }
}

public
extension VideoCompatible where Base: Codec.FFmpeg.Encoder {
    
    func open(config: Codec.FFmpeg.Video.Config) throws {
        try self.base.open(config: config)
    }
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedDataCallback) throws {
        try self.base.encode(bytes: bytes, size: size, displayTime: displayTime, onEncoded: onEncoded)
    }
    
}

//MARK: Video
private
extension Codec.FFmpeg.Encoder {
    
    func open(config: Codec.FFmpeg.Video.Config) throws {
        try self.videoSession = VideoSession.init(config: config)
    }
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onEncoded: @escaping EncodedDataCallback) throws {
        self.videoSession?.onEncodedData = onEncoded
        try videoSession?.encode(bytes: bytes, size: size, displayTime: displayTime)
    }

}
