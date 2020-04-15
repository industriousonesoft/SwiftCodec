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
    
    func open(config: Codec.FFmpeg.Video.Config, queue: DispatchQueue? = nil) throws {
        try self.base.open(config: config, queue: queue)
    }
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedDataCallback) {
        self.base.encode(bytes: bytes, size: size, displayTime: displayTime, onEncoded: onEncoded)
    }
    
}

//MARK: Video
private
extension Codec.FFmpeg.Encoder {
    
    func open(config: Codec.FFmpeg.Video.Config, queue: DispatchQueue? = nil) throws {
        try self.videoSession = VideoSession.init(config: config, queue: queue)
    }
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onEncoded: @escaping EncodedDataCallback) {
        self.videoSession?.onEncodedData = onEncoded
        videoSession?.encode(bytes: bytes, size: size, displayTime: displayTime)
    }

}
