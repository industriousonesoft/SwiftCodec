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
    
    func close() {
        self.base.closeVideoSession()
    }
    
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedDataCallback) {
        self.base.encode(bytes: bytes, size: size, displayTime: displayTime, onEncoded: onEncoded)
    }
    
}

//MARK: Video
private
extension Codec.FFmpeg.Encoder {
    
    func open(config: Codec.FFmpeg.Video.Config, queue: DispatchQueue? = nil) throws {
        try self.videoSession = VideoSession.init(config: config)
    }
    
    func closeVideoSession() {
        self.videoSession = nil
    }
  
    func encode(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onEncoded: @escaping EncodedDataCallback) {
        
        self.videoSession?.fill(bytes: bytes, size: size, onScaled: { (error) in
            if error != nil {
                onEncoded(nil, error)
            }else {
                self.videoSession?.encode(displayTime: displayTime, onEncoded: { (packet, error) in
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
        })
        
        
        
    }

}
