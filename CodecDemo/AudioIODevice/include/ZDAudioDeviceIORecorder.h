//
//  ZDAudioDeviceIORecorder.h
//  ZDAudioManager
//
//  Created by Georgy on 05/07/2018.
//  Copyright © 2018 Yinxiaoqi. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <CoreAudio/CoreAudio.h>
#import "ZDLocalAudioDefines.h"
#import "ZDAudioDevice.h"
typedef void (^ZDAudioDeviceIORecorderHandlerBlock)(AudioBuffer buffer, const AudioTimeStamp *inOutputTime);

@interface ZDAudioDeviceIORecorder : NSObject

- (instancetype)initWithDeviceUID:(NSString*)strUID;
@property (readonly) BOOL isRunning;
@property (readonly) int sampleRate;
@property (readonly) int channelCount;
@property (readonly) int bitsPerChannel;
@property (readonly) CGFloat  volume;
@property UInt32 bufferFrameSize;//count of frame every time.

- (BOOL) startWithDataHandler:(ZDAudioDeviceIORecorderHandlerBlock)handler;
- (void) stop;
@end
