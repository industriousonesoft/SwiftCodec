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
        
        public init() {}
    }
    
}

public
extension Codec.FFmpeg.Decoder {
    //MARK: - Video Config
    struct VideoConfig {
        
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
    
    //MARK: - Audio Config
    struct AudioConfig {
        
        public var codec: Codec.FFmpeg.Audio.CodecType
        public var srcPCMDesc: Codec.FFmpeg.Audio.PCMDescription
        public var dstPCMDesc: Codec.FFmpeg.Audio.PCMDescription
        
        public init(codec: Codec.FFmpeg.Audio.CodecType,
                    srcPCMDesc: Codec.FFmpeg.Audio.PCMDescription,
                    dstPCMDesc: Codec.FFmpeg.Audio.PCMDescription
        ) {
            self.codec = codec
            self.srcPCMDesc = srcPCMDesc
            self.dstPCMDesc = dstPCMDesc
        }
        
    }
}

extension Codec.FFmpeg.Decoder {
//    public typealias DecodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int)?, Error?) -> Void
    
    public typealias DecodedVideoCallback = (Data?, Error?) -> Void
    public typealias DecodedAudioCallback = ([Data]?, Error?) -> Void
  
    typealias DecodedFrameCallback = (UnsafeMutablePointer<AVFrame>?, Error?) -> Void
}
