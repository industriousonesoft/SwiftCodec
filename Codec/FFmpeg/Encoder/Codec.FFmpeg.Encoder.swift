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
        
        internal lazy var audioSession = {
            return AudioSession.init()
        }()
        
        internal lazy var videoSession = {
            return VideoSession.init()
        }()
    }
    
}

extension Codec.FFmpeg.Encoder {
    func close() {
        self.audioSession.close()
        self.videoSession.close()
    }
}
