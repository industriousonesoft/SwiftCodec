//
//  ZDLocalAudioDeviceOutput.h
//  cef
//
//  Created by Georgy on 9/24/16.
//
//

#import <Foundation/Foundation.h>
#import "ZDLocalAudioDefines.h"
//#define kOutputDeviceName   @"kOutputDeviceName"
//#define kOutputDeviceUID    @"kOutputDeviceUID"
//no -fno-objc-arc!
//only handle inverleaved audio data!

@class ZDAudioDevice;
typedef NSArray* (^ZDAudioOutputDataHandlerBlock)(void);

typedef struct sZDAudioParameter{
    bool isFloatFormat;
    int sampleRate;
    int channels;
    int bitsPerChannel;
}ZDAudioParameter;

@interface ZDLocalAudioDeviceOutput : NSObject
+ (NSArray<ZDAudioDevice*>*) outputDevices;

@property (readonly) PSStatus playerStatus;
@property (readonly) bool floatFormat;
@property (readonly) int sampleRate;
@property (readonly) int channelCount;
@property (readonly) int bitsPerChannel;
@property int32_t        synchronizeAudioTime;//cache length reach the time, it'll drop all cached data(in ms,default 500 ms).
@property (readonly) size_t bufferSize;//bytes;
@property CGFloat volume;

/*
 strUID == nil, use the default build-in system device.
 */
- (instancetype)initWithDeviceUID:(NSString*)strUID audioParmaeter:(ZDAudioParameter)param bufferSize:(size_t)size;
/*
 use the default build-in system device
 */
- (instancetype)initWithAudioParmaeter:(ZDAudioParameter)param bufferSize:(size_t)size;
- (BOOL) startWithDataHandler:(ZDAudioOutputDataHandlerBlock)handler;//必须要有数据才能开始play
- (void) pause;
- (void) stop;
@end
