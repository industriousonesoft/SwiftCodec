//
//  Codec.FFmpeg.Decoder.AudioSession.swift
//  SwiftCodec
//
//  Created by Mark Cao on 2020/4/28.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation
import CFFmpeg

private let ErrorDomain = "FFmpeg:Audio:Decoder"

extension Codec.FFmpeg.Decoder {
    class AudioSession {
        
        private var config: AudioConfig
        private var decodeQueue: DispatchQueue
        
        private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
        
        private var decodedFrame: UnsafeMutablePointer<AVFrame>?
     
        private var packet: UnsafeMutablePointer<AVPacket>?
        
        init(config: AudioConfig, decodeIn queue: DispatchQueue? = nil) {
            self.config = config
            self.decodeQueue = queue != nil ? queue! : DispatchQueue.init(label: "com.zdnet.ffmpeg.VideoSession.decode.queue")
        }
    }
}

extension Codec.FFmpeg.Decoder.AudioSession {
    
    func createCodecContext(config: Codec.FFmpeg.Decoder.AudioConfig) throws {
        
        let codecId = config.codec.avCodecID
        guard let codec = avcodec_find_decoder(codecId) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio codec.")!
        }
        
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            throw NSError.error(ErrorDomain, reason: "Can not create audio decode context...")!
        }
        codecCtx.pointee.codec_id = codecId
        codecCtx.pointee.codec_type = AVMEDIA_TYPE_AUDIO
        codecCtx.pointee.channel_layout = codec.pointee.channelLayout ?? UInt64(av_get_default_channel_layout(self.config.srcPCMDesc.channels))
        codecCtx.pointee.sample_rate = self.config.srcPCMDesc.sampleRate
        codecCtx.pointee.channels = self.config.srcPCMDesc.channels
        codecCtx.pointee.time_base.num = 1
        codecCtx.pointee.time_base.den = self.config.srcPCMDesc.sampleRate
        
        guard avcodec_open2(codecCtx, codec, nil) == 0 else {
            throw NSError.error(ErrorDomain, reason: "Can not open audio decode avcodec...")!
        }
        
        self.codecCtx = codecCtx
    }
    
    func destroyCodecCtx() {
        if let ctx = self.codecCtx {
            avcodec_close(ctx)
            avcodec_free_context(&self.codecCtx)
            self.codecCtx = nil
        }
    }
    
}
