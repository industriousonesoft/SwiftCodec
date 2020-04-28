//
//  Codec.FFmpeg.Decoder.Audio.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/28.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

public
extension Codec.FFmpeg.Decoder {
    
    var audio: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder> {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.init(self)
    }
    
    static var audio: Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.Type {
        return Codec.FFmpeg.AudioCompatible<Codec.FFmpeg.Decoder>.self
    }
}

public
extension Codec.FFmpeg.AudioCompatible where Base: Codec.FFmpeg.Decoder {
    
}

//MARK: - Decode Audio
extension Codec.FFmpeg.Decoder {
    
}
