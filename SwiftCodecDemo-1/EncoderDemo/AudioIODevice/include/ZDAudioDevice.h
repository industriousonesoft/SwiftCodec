//
//  ZDAudioDevice.h
//  CEFDemo
//
//  Created by Georgy on 03/12/2016.
//  Copyright © 2016 YuanDuan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

@interface ZDAudioDevice : NSObject
@property (readonly) NSString* name;
@property (readonly) NSString* UID;
@property (readonly) NSString* modelUID;
@property (readonly) UInt32    deviceID;
@property (readonly) BOOL      isBluetooth;
@property (readonly) BOOL      isBuildIn;
@property (readonly) BOOL      isOutput;
@property (readonly) BOOL      canBeDefaultDevice;

@property (readonly) AudioFormatID audioFormatID;
@property (readonly) AudioFormatFlags audioFormatFlags;
@property (readonly) int sampleRate;
@property (readonly) int channelCount;
@property (readonly) int bitsPerChannel;
@property (readonly) int bytesPerSample;
@property CGFloat volume;
@property UInt32 transportType;
//- (BOOL) canBecomeDefaultDevice:(BOOL)isInput;

- (instancetype)   initWithDeviceID:(UInt32)device;
+ (ZDAudioDevice*) DeviceWithUID:(NSString*)deviceUID;
+ (BOOL)           isValidToVisitMicroPhone;
//主线程调用：
//granted == YES：授权成功
//granted == NO： 需要用户主动打开系统隐私设置
//NSString *urlString = @"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone";
//[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
+ (void)           requestAccessForMicroPhone:(void (^)(BOOL granted))handler;
@end
