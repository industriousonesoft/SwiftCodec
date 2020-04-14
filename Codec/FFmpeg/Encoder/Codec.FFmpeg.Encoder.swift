//
//  Codec.FFmpeg.Encoder.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

extension Codec.FFmpeg {
    
    public class Encoder: NSObject {
        internal var audioSession: AudioSession? = nil
        internal var videoSession: VideoSession? = nil
    }
    
}

extension Codec.FFmpeg.Encoder {
    func close() {
        self.audioSession = nil
        self.videoSession = nil
    }
}
