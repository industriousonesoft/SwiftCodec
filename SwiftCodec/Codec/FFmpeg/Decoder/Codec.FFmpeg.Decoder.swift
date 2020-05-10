//
//  Codec.FFmpeg.Decoder.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/22.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

extension Codec.FFmpeg {
    public class Decoder {
        var videoSession: VideoSession? = nil
        var audioSession: AudioSession? = nil
        public init() {}
    }
    
}

public
extension Codec.FFmpeg.Decoder {
    
    struct Video {
        public
        struct Format {
            public var codec: Codec.FFmpeg.Video.CodecType
            public var bitRate: Int64
            public var fps: Int32
            public var outSize: CGSize
            public var srcPixelFmt: Codec.FFmpeg.Video.PixelFormat
            public var dstPixelFmt: Codec.FFmpeg.Video.PixelFormat
            
            public init(outSize: CGSize, codec: Codec.FFmpeg.Video.CodecType, bitRate: Int64, fps: Int32, srcPixelFmt: Codec.FFmpeg.Video.PixelFormat, dstPixelFmt: Codec.FFmpeg.Video.PixelFormat) {
                self.outSize = outSize
                self.codec = codec
                self.bitRate = bitRate
                self.fps = fps
                self.srcPixelFmt = srcPixelFmt
                self.dstPixelFmt = dstPixelFmt
            }
        }
    }
    
    struct Audio {
        public
        struct Format {
            public var codec: Codec.FFmpeg.Audio.CodecType
            public var srcPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            public var dstPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            
            public init(codec: Codec.FFmpeg.Audio.CodecType,
                        srcPCMSpec: Codec.FFmpeg.Audio.PCMSpec,
                        dstPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            ) {
                self.codec = codec
                self.srcPCMSpec = srcPCMSpec
                self.dstPCMSpec = dstPCMSpec
            }
            
        }
    }
    
}

extension Codec.FFmpeg.Decoder {
//    public typealias DecodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int)?, Error?) -> Void
    
//    public typealias DecodedVideoCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int)?, Error?) -> Void
    public typealias DecodedVideoCallback = (Data?, Error?) -> Void
//    public typealias DecodedAudioCallback = ([Data]?, Error?) -> Void
    public typealias DecodedAudioCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int)?, Error?) -> Void
  
    typealias DecodedFrameCallback = (UnsafeMutablePointer<AVFrame>?, Error?) -> Void
}
