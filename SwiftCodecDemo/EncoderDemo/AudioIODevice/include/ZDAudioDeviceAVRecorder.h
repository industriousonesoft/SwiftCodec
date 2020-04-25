//
//  ZDAudioDeviceAVRecorder.h
//  ZDAudioManagerDemo
//
//  Created by Georgy on 19/12/2016.
//  Copyright © 2016 YuanDuan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <CoreAudio/CoreAudio.h>
#import "ZDLocalAudioDefines.h"
#import "ZDAudioDevice.h"
typedef void (^ZDAudioDeviceAVRecorderHandlerBlock)(AudioBuffer buffer, const AudioTimeStamp *inOutputTime);
/*
 配合系统音频插件使用
 此类只用于从插件获取系统声音
 */
@interface ZDAudioDeviceAVRecorder : NSObject

/*
 如果strUID设备不存在，则返回nil
 */
- (instancetype)initWithDeviceUID:(NSString*)strUID;
@property (readonly) BOOL isRunning;
@property (readonly) int sampleRate;
@property (readonly) int channelCount;
@property (readonly) int bitsPerChannel;
@property (readonly) CGFloat  volume;
@property UInt32 bufferFrameSize;//count of frame every time.

- (BOOL) startWithDataHandler:(ZDAudioDeviceAVRecorderHandlerBlock)handler;
- (void) stop;
@end
