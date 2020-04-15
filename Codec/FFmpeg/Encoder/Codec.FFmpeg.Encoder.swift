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
        var muxerSession: MuxerSession? = nil
    }
    
}

extension Codec.FFmpeg.Encoder {
    public typealias MuxFormat = String
    public typealias EncodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
    public typealias MuxedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
    
    public struct MuxStreamFlags: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let Video = MuxStreamFlags.init(rawValue: 1 << 0)
        public static let Audio = MuxStreamFlags.init(rawValue: 1 << 1)
        
        public var videoOnly: Bool {
            return !self.contains(.Audio) && self.contains(.Video)
        }
        
        public var audioOnly: Bool {
            return self.contains(.Audio) && !self.contains(.Video)
        }
        
        public var both: Bool {
            return self.contains(.Audio) && self.contains(.Video)
        }
        
    }

    typealias EncodedPacketCallback = (UnsafeMutablePointer<AVPacket>?, Error?) -> Void
}

public extension Codec.FFmpeg.Encoder.MuxFormat {
    static let mpegts: String = "mpegts"
    static let h264: String = "h264"
}

