//
//  Codec.FFmpeg.Decoder.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/22.
//  Copyright © 2020 industriousonesoft. All rights reserved.
//

import Foundation
import CFFmpeg

extension Codec.FFmpeg {
    public class Decoder {
        var videoSession: Video.Session? = nil
        var audioSession: Audio.Session? = nil
        public init() {}
    }
}

//MARK: - Audio
public
extension Codec.FFmpeg.Decoder {
    
    struct Audio {
        public
        struct Format {
            public var codec: Codec.FFmpeg.Audio.CodecType
            public var srcPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            public var dstPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            
            public init(codec: Codec.FFmpeg.Audio.CodecType,
                        srcPCMSpec: Codec.FFmpeg.Audio.PCMSpec,
                        dstPCMSpec: Codec.FFmpeg.Audio.PCMSpec
            ) {
                self.codec = codec
                self.srcPCMSpec = srcPCMSpec
                self.dstPCMSpec = dstPCMSpec
            }
        }
        
        public
        class Frame {
//            private var bytes: UnsafeMutablePointer<UInt8>? = nil
//            private var size: Int = 0
//            private var filledSize: Int = 0
            public private(set) var data: Data? = nil
            let id: Int
            
            init(id: Int) {
                self.id = id
            }
            
            //FIXED: Only support packed sample format and 2 channels
            func assign(from buffer: UnsafePointer<UInt8>, size: Int) {
                self.data = Data.init(bytes: buffer, count: size)
            }
            /*
            private lazy var lockQueue: DispatchQueue = {
                return DispatchQueue.init(label: "com.wangcast.Codec.FFmpeg.Decoder.audio.frame-\(self.id)")
            }()
            
            //FIXED: Only support packed sample format and 2 channels
            func assign(from buffer: UnsafeMutablePointer<UInt8>, size: Int) {
                self.lockQueue.async { [unowned self] in
                    if self.bytes == nil {
                        self.bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
                        self.size = size
                        self.filledSize = size
                    }else if self.bytes != nil {
                        if self.size >= size {
                            self.bytes!.assign(from: buffer, count: size)
                            self.filledSize = size
                        }else {
                            print("Free and New - \(self.id)")
                            free(self.bytes!)
                            self.bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
                            self.size = size
                            self.filledSize = size
                        }
                    }
                }
            }
            
            public
            func read() -> (UnsafeMutablePointer<UInt8>?, Int) {
                var bytes: UnsafeMutablePointer<UInt8>? = nil
                var size: Int = 0
                self.lockQueue.sync { [unowned self] in
                    bytes = self.bytes
                    size = self.filledSize
                }
                return (bytes, size)
            }
             */
        }
    }
}

//MARK: - Video
public
extension Codec.FFmpeg.Decoder {
    
    struct Video {
        public
        struct Format {
            public var codec: Codec.FFmpeg.Video.CodecType
            public var bitRate: Int64
            public var fps: Int32
            public var outSize: CGSize
            public var srcPixelFmt: Codec.FFmpeg.Video.PixelFormat
            public var dstPixelFmt: Codec.FFmpeg.Video.PixelFormat
            
            public init(outSize: CGSize, codec: Codec.FFmpeg.Video.CodecType, bitRate: Int64, fps: Int32, srcPixelFmt: Codec.FFmpeg.Video.PixelFormat, dstPixelFmt: Codec.FFmpeg.Video.PixelFormat) {
                self.outSize = outSize
                self.codec = codec
                self.bitRate = bitRate
                self.fps = fps
                self.srcPixelFmt = srcPixelFmt
                self.dstPixelFmt = dstPixelFmt
            }
        }
        
        //由于frame中的属性需要动态更新，使用class避免copy-on-write
        public
        class Frame {
            public private(set) var data: Data? = nil
            let id: Int
            
            init(id: Int) {
                self.id = id
            }
        
            func assign(from frame: UnsafePointer<AVFrame>, pixFmt: Codec.FFmpeg.Video.PixelFormat) {
                if pixFmt == .YUV420P {
                   self.data = self.dumpYUV420(from: frame)
                }else if pixFmt == .RGB32 {
                    self.data = self.dumpRGB(from: frame)
                }
            }
            
            private
            func dumpYUV420(from frame: UnsafePointer<AVFrame>) -> Data? {
                    
                if let bytesY = frame.pointee.data.0,
                 let bytesU = frame.pointee.data.1,
                 let bytesV = frame.pointee.data.2 {
                    
        //            print("frame h: \(frame.pointee.height) - w: \(frame.pointee.width)")
                    //frame h: 1080 - w: 1920
        //            print("\(#function): \(frame.pointee.linesize.0) - \(frame.pointee.linesize.1) - \(frame.pointee.linesize.2)")
                    //1920 - 960 - 960
                    
                    //Method-01:
        //            let sizeY = frame.pointee.linesize.0 * frame.pointee.height
                    //Method-02
                    let sizeY = Int(frame.pointee.width * frame.pointee.height)
                  
                    var yuvData = Data.init(bytes: bytesY, count: sizeY)
                    yuvData.append(bytesU, count: sizeY / 4)
                    yuvData.append(bytesV, count: sizeY / 4)
                    
                    return yuvData
                }
                return nil
            }
            
            private
            func dumpRGB(from frame: UnsafePointer<AVFrame>) -> Data? {
                if let bytes = frame.pointee.data.0 {
                    let size = frame.pointee.width * frame.pointee.height
                    return Data.init(bytes: bytes, count: Int(size))
                }
                return nil
            }
        }
    }
    
}

extension Codec.FFmpeg.Decoder {
    public typealias DecodedVideoCallback = (Video.Frame?, Error?) -> Void
    public typealias DecodedAudioCallback = (Audio.Frame?, Error?) -> Void
}
