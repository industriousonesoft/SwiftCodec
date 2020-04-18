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
        var audioSession: AudioSession? = nil
        var videoSession: VideoSession? = nil
    }
    
}

extension Codec.FFmpeg.Encoder {
    public typealias EncodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
    public typealias ScaledCallback = (UnsafeMutablePointer<AVFrame>?, Error?) -> Void
    
    typealias EncodedPacketCallback = (UnsafeMutablePointer<AVPacket>?, Error?) -> Void
}
