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
        var muxSession: MuxSession? = nil
    }
    
}

extension Codec.FFmpeg.Encoder {
    public typealias MuxFormat = String
    public typealias EncodedDataCallback = ((UnsafeMutablePointer<UInt8>, Int32)?, Error?) -> Void
    public typealias MuxedDataCallback = ((UnsafeMutablePointer<UInt8>, Int32)?, Error?) -> Void
    
    public struct MuxStreamFlags: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let Video = MuxStreamFlags.init(rawValue: 1 << 0)
        public static let Audio = MuxStreamFlags.init(rawValue: 1 << 1)
        
    }

    typealias EncodedPacketCallback = (UnsafeMutablePointer<AVPacket>?, Error?) -> Void
}

public extension Codec.FFmpeg.Encoder.MuxFormat {
    static let mpegts = "mpegts"
}

public extension Codec.FFmpeg.Encoder {
    func close() {
        self.audioSession = nil
        self.videoSession = nil
    }
}
