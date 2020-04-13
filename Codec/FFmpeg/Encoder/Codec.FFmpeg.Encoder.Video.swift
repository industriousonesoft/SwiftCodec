//
//  Codec.FFmpeg.Encoder.Video.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

//MARK: - VideoCompatible
public struct VideoCompatible<Base> {
    let base: Base
    init(_ base: Base) {
        self.base = base
    }
}

public
extension Codec.FFmpeg.Encoder {
    
    var video: VideoCompatible<Codec.FFmpeg.Encoder> {
        return VideoCompatible<Codec.FFmpeg.Encoder>.init(self)
    }
    
    static var video: VideoCompatible<Codec.FFmpeg.Encoder>.Type {
        return VideoCompatible<Codec.FFmpeg.Encoder>.self
    }
}

public
extension AudioCompatible where Base: Codec.FFmpeg.Encoder {
    
}

//MARK: Video
private
extension Codec.FFmpeg.Encoder {
    
}
