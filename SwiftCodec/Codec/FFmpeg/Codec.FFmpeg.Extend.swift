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

//MARK: - AVCodec Extend
extension AVCodec {
    
    var sampleRate: Int32? {
        //supported_samplerates is a Int32 array contains all the supported samplerate
        guard let ptr: UnsafePointer<Int32> = self.supported_samplerates else {
            return nil
        }
        var bestSamplerate: Int32 = 0
        var index: Int = 0
        var cur = ptr.advanced(by: index).pointee
        while cur != 0 {
            if (bestSamplerate == 0 || abs(44100 - cur) < abs(44100 - bestSamplerate)) {
                bestSamplerate = cur
            }
            index += 1
            cur = ptr.advanced(by: index).pointee
        }
        return bestSamplerate
    }
    
    var channelLayout: UInt64? {
        
        guard let ptr: UnsafePointer<UInt64> = self.channel_layouts else {
            return nil
        }
        var bestChannelLayout: UInt64 = 0
        var bestChannels: Int32 = 0
        var index: Int = 0
        var cur = ptr.advanced(by: index).pointee
        while cur != 0 {
            let curChannels = av_get_channel_layout_nb_channels(cur)
            if curChannels > bestChannels {
                bestChannelLayout = cur
                bestChannels = curChannels
            }
            index += 1
            cur = ptr.advanced(by: index).pointee
        }
        return bestChannelLayout
    }
    
}

//MARK: - AVSampleFormat
extension AVSampleFormat {
    var isPacked: Bool {
        switch self {
        case AV_SAMPLE_FMT_U8, AV_SAMPLE_FMT_S16, AV_SAMPLE_FMT_S32, AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_DBL:
            return true
        case AV_SAMPLE_FMT_U8P, AV_SAMPLE_FMT_S16P, AV_SAMPLE_FMT_S32P, AV_SAMPLE_FMT_FLTP, AV_SAMPLE_FMT_DBLP:
            return false
        default:
            return false
        }
    }
}
