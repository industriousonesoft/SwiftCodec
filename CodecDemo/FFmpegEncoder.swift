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

private let DEFAULT_AUDIO_DEVICE_UID: String = "ZDAudioPlayThroughDevice_UID"

class FFmpegEncoder: NSObject {
    
    lazy var audioCapturer: AudioCapturer? = {
        return AudioCapturer.init(deviceUID: DEFAULT_AUDIO_DEVICE_UID)
    }()
    
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
        self.dataCacher.close()
        self.dataCacher.reset(fileName: "muxing.ts")
        try self.encoder.muxer.open(onMuxed: { [unowned self] (muxedData, err) in
            if err != nil {
                print("Error occured when encoding: \(err!.localizedDescription)")
            }else if let (bytes, size) = muxedData {
                let data = Data.init(bytes: bytes, count: Int(size))
                self.dataCacher.write(data: data)
                free(bytes)
            }
        })
        try self.openAudio()
        try self.openVideo()
    }
    
    func close() {
        self.stop()
        self.encoder.muxer.close()
    }
    
    func start() {
        self.startAudio()
        self.startVideo()
    }
    
    func stop() {
        self.stopAudio()
        self.stopVideo()
    }
}

//MARK: - Video
extension FFmpegEncoder {

    func openVideo() throws {
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
            try self.encoder.muxer.addVideoStream(config: config)
        }
    }
    
    func startVideo() {
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
    
    func stopVideo() {
        self.screenCapturer.stop()
    }
}

//MARK: - Audio
extension FFmpegEncoder {

    func openAudio() throws {
        
        guard let capturer = self.audioCapturer else {
            throw NSError.init(domain: #function, code: -1, userInfo: [NSLocalizedDescriptionKey : "No audio capturer found."])
        }
  
        guard let fmt = Codec.FFmpeg.Audio.Description.SampleFMT.wraps(from: capturer.audioFormatFlags) else {
            throw NSError.init(domain: #function, code: -1, userInfo: [NSLocalizedDescriptionKey : "Unsupported audio format flags: \(capturer.audioFormatFlags)"])
        }
        
        let inDesc = Codec.FFmpeg.Audio.Description.init(
            channels: capturer.channelCount,
            bitsPerChannel: capturer.bitsPerChannel,
            sampleRate: capturer.sampleRate,
            sampleFormat: fmt)
        
        let config = Codec.FFmpeg.Audio.Config.init(codec: .MP2, bitRate: 64000)
        
        try self.encoder.muxer.addAudioStream(in: inDesc, config: config)
    }
    
    func startAudio() {
        self.audioCapturer?.start { [unowned self] (bytes, size, displayTime) in
            if bytes != nil, size > 0 {
                self.encoder.muxer.muxingAudio(
                    bytes: bytes!,
                    size: size,
                    displayTime: Utilities.shared.machAbsoluteToSeconds(machAbsolute: displayTime)
                )
            }
        }
    }
    
    func stopAudio() {
        self.audioCapturer?.stop()
    }
}
