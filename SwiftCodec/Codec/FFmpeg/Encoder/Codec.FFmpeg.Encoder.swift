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
        var audioSession: Audio.Session? = nil
        var videoSession: Video.Session? = nil
        
        public init() {}
    }
    
}

public
extension Codec.FFmpeg.Encoder {
    
    struct Video {
        //MARK: - Video Config
        public
        struct Format {
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
    }

    //MARK: - Audio Config
    struct Audio {
        public
        struct Format {
            public var codec: Codec.FFmpeg.Audio.CodecType
            public var bitRate: Int64
            public var dstPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            public var srcPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            
            public init(codec: Codec.FFmpeg.Audio.CodecType, bitRate: Int64, srcPCMSpec: Codec.FFmpeg.Audio.PCMSpec, dstPCMSpec: Codec.FFmpeg.Audio.PCMSpec ) {
                self.codec = codec
                self.bitRate = bitRate
                self.srcPCMSpec = srcPCMSpec
                self.dstPCMSpec = dstPCMSpec
            }
            
        }
    }
}

extension Codec.FFmpeg.Encoder {
    public
    typealias EncodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
  
    typealias EncodedPacketCallback = (UnsafeMutablePointer<AVPacket>?, Error?) -> Void
}
