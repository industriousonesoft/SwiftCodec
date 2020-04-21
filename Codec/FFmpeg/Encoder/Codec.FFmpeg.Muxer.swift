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
    
    enum MuxingMode {
        //低延时，存在视频掉帧
        case RealTime
        //高延时，音视频完整
        case Dump
    }
    
    struct StreamFlags: OptionSet {
        
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let Video = StreamFlags.init(rawValue: 1 << 0)
        public static let Audio = StreamFlags.init(rawValue: 1 << 1)
        
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
    
    var flags: StreamFlags? {
        get {
            return self.muxerSession?.flags
        }
    }
    
    var mode: MuxingMode? {
        get {
            self.muxerSession?.mode
        }
    }
    
    func open(mode: MuxingMode, flags: StreamFlags, onMuxed: @escaping MuxedDataCallback, queue: DispatchQueue? = nil) throws {
        self.muxerSession = try MuxerSession.init(mode: mode, flags: flags, onMuxed: onMuxed, queue: queue)
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
    
    func muxingVideo(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double, onScaled: @escaping Codec.FFmpeg.Encoder.ScaledCallback) {
        self.muxerSession?.muxingVideo(bytes: bytes, size: size, displayTime: displayTime, onScaled: onScaled)
    }
    
    func muxingAudio(bytes: UnsafeMutablePointer<UInt8>, size: Int32, displayTime: Double) {
        self.muxerSession?.muxingAudio(bytes: bytes, size: size, displayTime: displayTime)
    }
}
