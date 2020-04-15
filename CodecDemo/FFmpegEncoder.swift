//
//  FFmpegEncoder.swift
//  CodecDemo
//
//  Created by Mark Cao on 2020/4/15.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import SwiftyDesktopCapturer
import SwiftyCodec

class FFmpegEncoder: NSObject {
    
    lazy var screenCapturer: ScreenCapturer = {
        return DesktopCapturer.createDesktopCapturer(.screen) as! ScreenCapturer
    }()
    
    lazy var encoder: Codec.FFmpeg.Encoder = {
       return Codec.FFmpeg.Encoder.init()
    }()
    
    lazy var dataCacher: DataCacher = {
        return DataCacher.init()
    }()
    
    lazy var encodeQueue: DispatchQueue = {
        return DispatchQueue.init(label: "com.zdnet.FFmpegEncoder.queue")
    }()
    
    private var currDesktopItem: AnyObject? = nil
}

extension FFmpegEncoder {
    
    func open() throws {
        let displays = self.screenCapturer.getSourceList()
        if let item = displays.filter({ return $0.isMainDisplay == true }).first {
            self.currDesktopItem = item
            let config = Codec.FFmpeg.Video.Config.init(
                outSize: .init(width: 1280, height: 720),
                codec: .H264,
                bitRate: 1000000,
                fps: 25,
                gopSize: 50,
                dropB: true
            )
            self.dataCacher.close()
            self.dataCacher.reset(fileName: "muxing.h264")
            try self.encoder.muxer.open(format: .h264, onMuxed: { [unowned self] (muxedData, err) in
                if err != nil {
                    print("Error occured when encoding: \(err!.localizedDescription)")
                }else if let (bytes, size) = muxedData {
                    let data = Data.init(bytes: bytes, count: Int(size))
                    self.dataCacher.write(data: data)
                    free(bytes)
                }
                
            })
            
            try self.encoder.muxer.addVideoStream(config: config)
        }
    }
    
    func close() {
        self.encoder.muxer.close()
    }
    
    func start() {
        if let item = self.currDesktopItem {
            self.screenCapturer.start(item: item, onSucceed: { (error) in
                if error != nil {
                    print("Failed to capture screen.")
                }
            }) { [unowned self] (result, frame, displayTime) in
                if result == .success {
                    if let bytes = frame?.bytes {
                        self.encodeQueue.async { [unowned self] in
                            self.encoder.muxer.muxingVideo(
                                bytes: bytes,
                                size: frame!.size,
                                displayTime: Utilities.shared.machAbsoluteToSeconds(machAbsolute: displayTime)
                            )
                            /*
                                    self.encoder.video.encode(
                                    bytes: bytes,
                                    size: frame!.size,
                                    displayTime: Utilities.shared.machAbsoluteToSeconds(machAbsolute: displayTime),
                                    onEncoded: { (encodedFrame, error) in
                                        if error != nil {
                                            print("Error occured when encoding: \(error!.localizedDescription)")
                                        }else if let (bytes, size) = encodedFrame {
                                            let data = Data.init(bytes: bytes, count: Int(size))
                                            self.dataCacher.write(data: data)
                                        }
                                })
                                */
                        
                        }
                    }
                }else if result == .temporaryErr {
                    print("Temporary Error Occured.")
                }else if result == .permanentErr {
                    print("Permanent Error Occured.")
                }
            }
        }
    }
}
