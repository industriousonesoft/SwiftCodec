//
//  Codec.FFmpeg.Encoder.Video.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 industriousonesoft. All rights reserved.
//

import Foundation
import CFFmpeg

public
extension Codec.FFmpeg.Encoder {
    
    var video: Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Encoder> {
        return Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Encoder>.init(self)
    }
    
    static var video: Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Encoder>.Type {
        return Codec.FFmpeg.VideoCompatible<Codec.FFmpeg.Encoder>.self
    }
}

public
extension Codec.FFmpeg.VideoCompatible where Base: Codec.FFmpeg.Encoder {
    
    func open(format: Codec.FFmpeg.Encoder.Video.Format, queue: DispatchQueue? = nil) throws {
        try self.base.open(format: format, queue: queue)
    }
    
    func close() {
        self.base.closeVideoSession()
    }
    
    func fill(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, onFinished: @escaping (Error?) -> Void) {
        self.base.fill(bytes: bytes, size: size, onFinished: onFinished)
    }
    
    func encode(displayTime: Double, onEncoded: @escaping Codec.FFmpeg.Encoder.EncodedDataCallback) {
        self.base.encode(displayTime: displayTime, onEncoded: onEncoded)
    }
}

//MARK: Video
private
extension Codec.FFmpeg.Encoder {
    
    func open(format: Video.Format, queue: DispatchQueue? = nil) throws {
        try self.videoSession = Video.Session.init(format: format)
    }
    
    func closeVideoSession() {
        self.videoSession = nil
    }
    
    func fill(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, onFinished: @escaping (Error?) -> Void) {
        self.videoSession?.fill(bytes: bytes, size: size, onFinished: onFinished)
    }
  
    func encode(displayTime: Double, onEncoded: @escaping EncodedDataCallback) {
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

}
