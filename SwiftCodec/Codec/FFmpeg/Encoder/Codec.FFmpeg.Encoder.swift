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
        public var srcPixelFmt: Codec.FFmpeg.Video.PixelFormat
        public var dstPixelFmt: Codec.FFmpeg.Video.PixelFormat
        
        public init(outSize: CGSize, codec: Codec.FFmpeg.Video.CodecType, bitRate: Int64, fps: Int32, gopSize: Int32, dropB: Bool, srcPixelFmt: Codec.FFmpeg.Video.PixelFormat, dstPixelFmt: Codec.FFmpeg.Video.PixelFormat) {
            self.outSize = outSize
            self.codec = codec
            self.bitRate = bitRate
            self.fps = fps
            self.gopSize = gopSize
            self.dropB = dropB
            self.srcPixelFmt = srcPixelFmt
            self.dstPixelFmt = dstPixelFmt
        }
    }
    
    //MARK: - Audio Config
    struct AudioConfig {
        
        public var codec: Codec.FFmpeg.Audio.CodecType
        public var bitRate: Int64
        public var dstPCMDesc: Codec.FFmpeg.Audio.PCMDescription
        public var srcPCMDesc: Codec.FFmpeg.Audio.PCMDescription
        
        public init(codec: Codec.FFmpeg.Audio.CodecType, bitRate: Int64, srcPCMDesc: Codec.FFmpeg.Audio.PCMDescription, dstPCMDesc: Codec.FFmpeg.Audio.PCMDescription ) {
            self.codec = codec
            self.bitRate = bitRate
            self.srcPCMDesc = srcPCMDesc
            self.dstPCMDesc = dstPCMDesc
        }
        
    }
}

extension Codec.FFmpeg.Encoder {
    public
    typealias EncodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
  
    typealias EncodedPacketCallback = (UnsafeMutablePointer<AVPacket>?, Error?) -> Void
}
