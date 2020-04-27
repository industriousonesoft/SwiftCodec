//
//  Codec.FFmpeg.Encoder.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

extension Codec.FFmpeg {
    public class Encoder {
        var audioSession: AudioSession? = nil
        var videoSession: VideoSession? = nil
        
        public init() {}
    }
    
}

public
extension Codec.FFmpeg.Encoder {
    //MARK: - Video Config
    struct VideoConfig {
        
        public var codec: Codec.FFmpeg.Video.CodecType
        public var bitRate: Int64
        public var fps: Int32
        public var gopSize: Int32
        public var dropB: Bool
        public var outSize: CGSize
        public var pixelFmt: Codec.FFmpeg.Video.PixelFormat
        
        public init(outSize: CGSize, codec: Codec.FFmpeg.Video.CodecType, bitRate: Int64, fps: Int32, gopSize: Int32, dropB: Bool, pixelFmt: Codec.FFmpeg.Video.PixelFormat) {
            self.outSize = outSize
            self.codec = codec
            self.bitRate = bitRate
            self.fps = fps
            self.gopSize = gopSize
            self.dropB = dropB
            self.pixelFmt = pixelFmt
        }
    }
    
    //MARK: - Audio Config
    struct AudioConfig {
        
        public var codec: Codec.FFmpeg.Audio.CodecType
        public var bitRate: Int64
        public var pcmDesc: Codec.FFmpeg.Audio.PCMDescription
        
        public init(pcmDesc: Codec.FFmpeg.Audio.PCMDescription, codec: Codec.FFmpeg.Audio.CodecType, bitRate: Int64) {
            self.codec = codec
            self.bitRate = bitRate
            self.pcmDesc = pcmDesc
        }
        
    }
}

extension Codec.FFmpeg.Encoder {
    public
    typealias EncodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
  
    typealias EncodedPacketCallback = (UnsafeMutablePointer<AVPacket>?, Error?) -> Void
}
