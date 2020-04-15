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
                codec: .MPEG1,
                bitRate: 1000000,
                fps: 25,
                gopSize: 50,
                dropB: true
            )
            try self.encoder.video.open(config: config)
        }
    }
    
    func close() {
        self.encoder.close()
    }
    
    func start() {
        if let item = self.currDesktopItem {
            self.dataCacher.close()
            self.dataCacher.reset(fileName: "Encoded.data")
            self.screenCapturer.start(item: item, onSucceed: { (error) in
                if error != nil {
                    print("Failed to capture screen.")
                }
            }) { [unowned self] (result, frame, displayTime) in
                if result == .success {
                    if let bytes = frame?.bytes {
                        self.encodeQueue.async { [unowned self] in
                            do {
                                try self.encoder.video.encode(
                                    bytes: bytes,
                                    size: frame!.size,
                                    displayTime: Utilities.shared.machAbsoluteToSeconds(machAbsolute: displayTime),
                                    onEncoded: { (encodedFrame, error) in
                                        if error != nil {
                                            print("Error occured when encoding: \(error!.localizedDescription)")
                                        }else if encodedFrame != nil {
                                            let data = Data.init(bytes: encodedFrame!.bytes, count: Int(encodedFrame!.size))
                                            self.dataCacher.write(data: data)
                                        }
                                })
                            }catch let err {
                                print("Failed to encode: \(err.localizedDescription)")
                            }
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
