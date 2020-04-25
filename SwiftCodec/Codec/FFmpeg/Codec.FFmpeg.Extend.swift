//
//  Codec.FFmpeg.Extend.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/25.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

//MARK: - AVFrame Extend
extension AVFrame {
    var sliceArray: [UnsafePointer<UInt8>?] {
        mutating get {
             return [
                UnsafePointer<UInt8>(self.data.0),
                UnsafePointer<UInt8>(self.data.1),
                UnsafePointer<UInt8>(self.data.2),
                UnsafePointer<UInt8>(self.data.3),
                UnsafePointer<UInt8>(self.data.4),
                UnsafePointer<UInt8>(self.data.5),
                UnsafePointer<UInt8>(self.data.6),
                UnsafePointer<UInt8>(self.data.7)
            ]
        }
    }
    
    var mutablleSliceArray: [UnsafeMutablePointer<UInt8>?] {
        mutating get {
             return [
                UnsafeMutablePointer<UInt8>(self.data.0),
                UnsafeMutablePointer<UInt8>(self.data.1),
                UnsafeMutablePointer<UInt8>(self.data.2),
                UnsafeMutablePointer<UInt8>(self.data.3),
                UnsafeMutablePointer<UInt8>(self.data.4),
                UnsafeMutablePointer<UInt8>(self.data.5),
                UnsafeMutablePointer<UInt8>(self.data.6),
                UnsafeMutablePointer<UInt8>(self.data.7)
            ]
        }
    }
    
    var strideArray: [Int32] {
        mutating get {
            return [
                self.linesize.0,
                self.linesize.1,
                self.linesize.2,
                self.linesize.3,
                self.linesize.4,
                self.linesize.5,
                self.linesize.6,
                self.linesize.7
            ]
        }
    }
}
