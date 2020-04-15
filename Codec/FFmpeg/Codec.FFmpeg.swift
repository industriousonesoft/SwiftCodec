//
//  FFmpegCodec.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CoreAudio
@_exported import CFFmpeg
@_exported import FFmepgWrapperOCBridge

public extension Codec {
    struct FFmpeg {
        public static let SWIFT_AV_SAMPLE_FMT_S16: Int32 = AV_SAMPLE_FMT_S16.rawValue
        public static let SWIFT_AV_SAMPLE_FMT_S16P: Int32 = AV_SAMPLE_FMT_S16P.rawValue
        public static let SWIFT_AV_SAMPLE_FMT_FLT: Int32 = AV_SAMPLE_FMT_FLT.rawValue
        public static let SWIFT_AV_SAMPLE_FMT_FLTP: Int32 = AV_SAMPLE_FMT_FLTP.rawValue
        
        static let SWIFT_AV_PIX_FMT_RGB32 = AVPixelFormat(FFmepgWrapperOCBridge.avPixelFormatRGB32())
        static let SWIFT_AV_ERROR_EOF = FFmepgWrapperOCBridge.avErrorEOF()
        static let SWIFT_AV_ERROR_EAGAIN = FFmepgWrapperOCBridge.avErrorEagain()
        static let SWIFT_AC_NOPTS_VALUE = FFmepgWrapperOCBridge.avNoPTSValue()
    }
}

 //MARK: - Audio
public extension Codec.FFmpeg {

    struct Audio {
        
        //MARK: - Description
        public struct Description: Equatable {
            
            public enum SampleFMT {
                case S16
                case S16P
                case FLT
                case FLTP
                
                public func toAVSampleFormat() -> AVSampleFormat {
                    switch self {
                    case .S16:
                        return AVSampleFormat(AV_SAMPLE_FMT_S16.rawValue)
                    case .S16P:
                        return AVSampleFormat(AV_SAMPLE_FMT_S16P.rawValue)
                    case .FLT:
                        return AVSampleFormat(AV_SAMPLE_FMT_FLT.rawValue)
                    case .FLTP:
                        return AVSampleFormat(AV_SAMPLE_FMT_FLTP.rawValue)
                    }
                }
            }
            
            public var sampleRate: Int32
            public var channels: Int32
            public var bitsPerChannel: Int32
            public var sampleFormat: SampleFMT
            
            public func sampleFMT(from flags: AudioFormatFlags) -> SampleFMT? {
                if (flags & kAudioFormatFlagIsFloat) != 0 && (flags & kAudioFormatFlagIsNonInterleaved) != 0 {
                    return .FLTP
                }else if (flags & kAudioFormatFlagIsFloat) != 0 && (flags & kAudioFormatFlagIsPacked) != 0 {
                    return .FLT
                }else if (flags & kAudioFormatFlagIsSignedInteger) != 0 && (flags & kAudioFormatFlagIsPacked) != 0 {
                    return .S16
                }else if (flags & kAudioFormatFlagIsSignedInteger) != 0 && (flags & kAudioFormatFlagIsNonInterleaved) != 0 {
                    return .S16P
                }else {
                    return nil
                }
            }
            
            public static func == (lhs: Self, rhs: Self) -> Bool {
                return lhs.sampleRate == rhs.sampleRate &&
                        lhs.channels == rhs.channels &&
                        lhs.bitsPerChannel == rhs.bitsPerChannel &&
                        lhs.sampleFormat == rhs.sampleFormat
            }
        }

        //MARK: - Config
        public struct Config {
            
            public enum CodecType {
                case MP2
                case AAC
                public func toAVCodecID() -> AVCodecID {
                    switch self {
                    case .MP2:
                        return AV_CODEC_ID_MP2
                    case .AAC:
                        return AV_CODEC_ID_AAC
                    }
                }
            }
            
            public var codec: CodecType
            public var bitRate: Int64
            
            internal static let defaultDesc = Audio.Description.init(sampleRate: Int32(44100), channels: Int32(2), bitsPerChannel: Int32(16), sampleFormat: .S16)
        }
    }
}

//MARK: - Video
public extension Codec.FFmpeg {
    
    struct Video {
        //MARK: - Config
        public struct Config {
            
            public enum CodecType {
                case MPEG1
                case H264
                public func toAVCodecID() -> AVCodecID {
                    switch self {
                    case .MPEG1:
                        return AV_CODEC_ID_MPEG1VIDEO
                    case .H264:
                        return AV_CODEC_ID_H264
                    }
                }
            }
            
            public var codec: CodecType
            public var bitRate: Int64
            public var fps: Int32
            public var gopSize: Int32
            public var dropB: Bool
            public var outSize: CGSize
            
            public init(outSize: CGSize, codec: CodecType, bitRate: Int64, fps: Int32, gopSize: Int32, dropB: Bool) {
                self.outSize = outSize
                self.codec = codec
                self.bitRate = bitRate
                self.fps = fps
                self.gopSize = gopSize
                self.dropB = dropB
            }
        }
    }
}

