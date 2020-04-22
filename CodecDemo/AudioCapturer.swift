//
//  AudioCapturer.swift
//  TryVNCDemo-Telegraph
//
//  Created by caowanping on 2019/12/16.
//  Copyright © 2019 zdnet. All rights reserved.
//

import Foundation
import AudioManager

typealias OnAudioCaptured = (_ pcmBytes: UnsafeMutablePointer<UInt8>?, _ len: Int32, _ displayTime: UInt64) -> Void

class AudioCapturer {
    
    var recorder: ZDAudioDeviceAVRecorder!
    var device: ZDAudioDevice!
    
    var isRunning: Bool {
        get {
            return self.recorder.isRunning
        }
    }
    
    var sampleRate: Int32 {
        get {
            return self.device.sampleRate
        }
    }
    
    var channelCount: Int32 {
        get {
            return self.device.channelCount
        }
    }
    
    var bitsPerChannel: Int32 {
        get {
            return self.device.bitsPerChannel
        }
    }
    
    var volume: CGFloat {
        get {
            return self.device.volume
        }
    }
    var audioFormatID: AudioFormatID {
        get {
            return self.device.audioFormatID
        }
    }
    
    var audioFormatFlags: AudioFormatFlags {
        get {
            return self.device.audioFormatFlags
        }
    }
    
    init?(deviceUID: String) {
        
        if let audioDevices = ZDLocalAudioDeviceManager.default()?.audioDevices() as? [ZDAudioDevice],
            let filter = audioDevices.filter({ return $0.uid == deviceUID }).first {
            self.device = filter
            self.recorder = ZDAudioDeviceAVRecorder.init(deviceUID: deviceUID)
        }else {
//            fatalError("No audio device found.")
            return nil
        }
        
    }
    
}

extension AudioCapturer {
    
    func start(onCapture: @escaping OnAudioCaptured) {
        self.recorder.start { (buffer: AudioBuffer, timestamp: UnsafePointer<AudioTimeStamp>?) in
            onCapture(buffer.mData?.assumingMemoryBound(to: UInt8.self), Int32(buffer.mDataByteSize), mach_absolute_time())
        }
    }
    
    func stop() {
        self.recorder.stop()
    }
}
