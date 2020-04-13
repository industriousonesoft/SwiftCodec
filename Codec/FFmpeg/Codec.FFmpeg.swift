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

extension Codec {
    public struct FFmpeg {
        
        //MARK: - AudioDescription
        public struct AudioDescription: Equatable {
            
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

        //MARK: - AudioDescription
        public struct Config {
            
            public enum CodecType {
                case MP2
                public func toAVCodecID() -> AVCodecID {
                    switch self {
                    case .MP2:
                        return AV_CODEC_ID_MP2
                    }
                }
            }
            
            public var codec: CodecType
            public var bitRate: Int64
            
            internal static let defaultDesc = AudioDescription.init(sampleRate: Int32(44100), channels: Int32(2), bitsPerChannel: Int32(16), sampleFormat: .S16)
        }
    }
}



