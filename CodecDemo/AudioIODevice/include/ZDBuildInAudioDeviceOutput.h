//
//  ZDBuildInAudioDeviceOutput.h
//  cef
//
//  Created by Georgy on 5/7/19.
//
//

#import <Foundation/Foundation.h>
#include <CoreAudio/CoreAudio.h>
#import "ZDLocalAudioDefines.h"
@interface ZDAudioPCMPacket : NSObject 
@property NSData* data;
@property AudioTimeStamp outputTimestamp;
@end;

@class ZDAudioDevice;

typedef NSArray* (^ZDBuildInAudioDeviceOutputDataHandlerBlock)(void);//返回的ZDAudioPCMPacket

@interface ZDBuildInAudioDeviceOutput : NSObject

@property (readonly) BOOL   isRunning;
@property (readonly) UInt32 bufferFrameSize;//bytes;

- (instancetype)initWithDeviceId:(UInt32)deviceID bufferFrameSize:(UInt32)size;
- (BOOL) startWithDataHandler:(ZDBuildInAudioDeviceOutputDataHandlerBlock)handler;//必须要有数据才能开始play
- (void) stop;
@end

