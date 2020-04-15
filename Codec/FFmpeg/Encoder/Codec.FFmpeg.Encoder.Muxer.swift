//
//  Codec.FFmpeg.Encoder.Muxer.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

//MARK: - Muxer Compatible
public struct MuxerCompatible<Base> {
    let base: Base
    init(_ base: Base) {
        self.base = base
    }
}

public
extension Codec.FFmpeg.Encoder {
    
    var muxer: MuxerCompatible<Codec.FFmpeg.Encoder> {
        return MuxerCompatible<Codec.FFmpeg.Encoder>.init(self)
    }
    
    static var muxer: MuxerCompatible<Codec.FFmpeg.Encoder>.Type {
        return MuxerCompatible<Codec.FFmpeg.Encoder>.self
    }
}

public
extension MuxerCompatible where Base: Codec.FFmpeg.Encoder {
    
    func open(format: Codec.FFmpeg.Encoder.MuxFormat, onMuxed: @escaping Codec.FFmpeg.Encoder.MuxedDataCallback, queue: DispatchQueue? = nil) throws {
        try self.base.open(format: format, onMuxed: onMuxed, queue: queue)
    }
    
    func close() {
        self.base.closeMuxerSession()
    }
    
    func addAudioStream(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        try self.base.addAudioStream(in: desc, config: config)
    }
    
    func addVideoStream(config: Codec.FFmpeg.Video.Config) throws {
        try self.base.addVideoStream(config: config)
    }
    
    func muxingVideo(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double) {
        self.base.muxingVideo(bytes: bytes, size: size, displayTime: displayTime)
    }
    
    func muxingAudio(bytes: UnsafeMutablePointer<UInt8>, size: Int32) {
        self.base.muxingAudio(bytes: bytes, size: size)
    }
}

//MARK: Muxer
private
extension Codec.FFmpeg.Encoder {
    
    func open(format: Codec.FFmpeg.Encoder.MuxFormat, onMuxed: @escaping Codec.FFmpeg.Encoder.MuxedDataCallback, queue: DispatchQueue? = nil) throws {
        self.muxerSession = try MuxerSession.init(format: format, onMuxed: onMuxed, queue: queue)
    }
    
    func closeMuxerSession() {
        self.muxerSession = nil
    }
    
    func addAudioStream(in desc: Codec.FFmpeg.Audio.Description, config: Codec.FFmpeg.Audio.Config) throws {
        try self.muxerSession?.addAudioStream(in: desc, config: config)
    }
    
    func addVideoStream(config: Codec.FFmpeg.Video.Config) throws {
        try self.muxerSession?.addVideoStream(config: config)
    }
    
    func muxingVideo(bytes: UnsafeMutablePointer<UInt8>, size: CGSize, displayTime: Double) {
        self.muxerSession?.muxingVideo(bytes: bytes, size: size, displayTime: displayTime)
    }
    
    func muxingAudio(bytes: UnsafeMutablePointer<UInt8>, size: Int32) {
        self.muxerSession?.muxingAudio(bytes: bytes, size: size)
    }
}
