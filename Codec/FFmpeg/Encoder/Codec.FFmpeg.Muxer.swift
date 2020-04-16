//
//  Codec.FFmpeg.Encoder.Muxer.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

extension Codec.FFmpeg {
    public class Muxer: NSObject {
        var muxerSession: MuxerSession? = nil
    }
}

public
extension Codec.FFmpeg.Muxer {
    
    typealias MuxedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
    
    struct MuxStreamFlags: OptionSet {
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
    
}

public
extension Codec.FFmpeg.Muxer {
    
    func open(flags: MuxStreamFlags, onMuxed: @escaping MuxedDataCallback, queue: DispatchQueue? = nil) throws {
        self.muxerSession = try MuxerSession.init(flags: flags, onMuxed: onMuxed, queue: queue)
    }
    
    func close() {
        self.muxerSession = nil
    }
    
    func setAudioStream(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        try self.muxerSession?.setAudioStream(in: desc, config: config)
    }
    
    func setVideoStream(config: Codec.FFmpeg.Video.Config) throws {
        try self.muxerSession?.setVideoStream(config: config)
    }
    
    func muxingVideo(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double) {
        self.muxerSession?.muxingVideo(bytes: bytes, size: size, displayTime: displayTime)
    }
    
    func muxingAudio(bytes: UnsafeMutablePointer<UInt8>, size: Int32, displayTime: Double) {
        self.muxerSession?.muxingAudio(bytes: bytes, size: size, displayTime: displayTime)
    }
}
