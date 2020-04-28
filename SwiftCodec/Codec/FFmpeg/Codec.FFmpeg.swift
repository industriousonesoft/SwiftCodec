//
//  FFmpegCodec.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/13.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CoreAudio
import CFFmpeg
@_exported import FFmepgOCBridge

public extension Codec {
    
    class FFmpeg {
        
        static let SWIFT_AV_ERROR_EOF = FFmepgOCBridge.avErrorEOF()
        static let SWIFT_AV_ERROR_EAGAIN = FFmepgOCBridge.avErrorEagain()
        static let SWIFT_AV_NOPTS_VALUE = FFmepgOCBridge.avNoPTSValue()
   
    }
}

public extension Codec.FFmpeg {
    //MARK: - VideoCompatible
    struct VideoCompatible<Base> {
        let base: Base
        init(_ base: Base) {
            self.base = base
        }
    }

      //MARK: - AudioCompatible
    struct AudioCompatible<Base> {
        let base: Base
        init(_ base: Base) {
            self.base = base
        }
    }
}

//MARK: - AVLog
public extension Codec.FFmpeg {
    
    typealias AVLogCallback = (String) -> Void
    
    static func setAVLog(callback: @escaping AVLogCallback) {
        FFmepgOCBridge.setAVLog { (log) in
            if log != nil {
                callback(log!)
            }
        }
    }
}

//MARK: - Audio
public extension Codec.FFmpeg {

    struct Audio {
        
        public enum SampleFormat {
            case S16
            case S16P
            case FLT
            case FLTP
            
            var avSampleFmt: AVSampleFormat {
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
            
            public static func wraps(from flags: AudioFormatFlags) -> SampleFormat? {
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
            
        }
        
        //MARK: - Description
        public struct PCMDescription: Equatable {
        
            public var sampleRate: Int32
            public var channels: Int32
            public var bitsPerChannel: Int32
            public var sampleFmt: SampleFormat
            
            public init(channels: Int32, bitsPerChannel: Int32, sampleRate: Int32, sampleFmt: SampleFormat) {
                self.channels = channels
                self.bitsPerChannel = bitsPerChannel
                self.sampleRate = sampleRate
                self.sampleFmt = sampleFmt
            }
            
            public static func == (lhs: Self, rhs: Self) -> Bool {
                return lhs.sampleRate == rhs.sampleRate &&
                        lhs.channels == rhs.channels &&
                        lhs.bitsPerChannel == rhs.bitsPerChannel &&
                        lhs.sampleFmt == rhs.sampleFmt
            }
        }
        
        //MARK: Codec Type
        public enum CodecType {
            case MP2
            case AAC
            
            var avCodecID: AVCodecID {
                switch self {
                case .MP2:
                    return AV_CODEC_ID_MP2
                case .AAC:
                    return AV_CODEC_ID_AAC
                }
            }
        }
        
    }
}

//MARK: - Video
public extension Codec.FFmpeg {
    
    struct Video {
        
        public enum PixelFormat {
            case YUV420P
            case RGB32
            
            var avPixelFormat: AVPixelFormat {
                switch self {
                case .YUV420P:
                    return AV_PIX_FMT_YUV420P
                case .RGB32:
                    return AVPixelFormat(FFmepgOCBridge.avPixelFormatRGB32())
                }
            }
            
        }
        
        public enum CodecType {
            case MPEG1
            case H264
            
            var avCodecID: AVCodecID {
                switch self {
                case .MPEG1:
                    return AV_CODEC_ID_MPEG1VIDEO
                case .H264:
                    return AV_CODEC_ID_H264
                }
            }
            
            var pixelFmt: PixelFormat {
                switch self {
                case .MPEG1:
                    return .YUV420P
                case .H264:
                    return .YUV420P
                }
            }
        }
        
    }
}

