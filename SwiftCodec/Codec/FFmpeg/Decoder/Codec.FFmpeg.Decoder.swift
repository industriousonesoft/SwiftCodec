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
        public var pixelFmt: Codec.FFmpeg.Video.PixelFormat
        
        public init(outSize: CGSize, codec: Codec.FFmpeg.Video.CodecType, bitRate: Int64, fps: Int32, pixelFmt: Codec.FFmpeg.Video.PixelFormat) {
            self.outSize = outSize
            self.codec = codec
            self.bitRate = bitRate
            self.fps = fps
            self.pixelFmt = pixelFmt
        }
    }
}

extension Codec.FFmpeg.Decoder {
//    public typealias DecodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int)?, Error?) -> Void
    
    public typealias DecodedDataCallback = (Data?, Error?) -> Void
  
    typealias DecodedFrameCallback = (UnsafeMutablePointer<AVFrame>?, Error?) -> Void
}
