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

extension Codec.FFmpeg.Decoder {
    public
    typealias DecodedDataCallback = ((bytes: UnsafeMutablePointer<UInt8>, size: Int32)?, Error?) -> Void
  
    typealias DecodedFrameCallback = (UnsafeMutablePointer<AVFrame>?, Error?) -> Void
}
