//
//  ZDLocalAudioDeviceManager.h
//  ZDAudioManagerDemo
//
//  Created by Georgy on 05/01/2017.
//  Copyright © 2017 YuanDuan. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ZDAudioDevice;
#define kLocalAudioDevicesChangedNotification @"kLocalAudioDevicesChangedNotification"
@interface ZDLocalAudioDeviceManager : NSObject
+ (instancetype)   defaultManager;
- (NSArray*)       AudioDevices;
- (ZDAudioDevice*) DefaultOutputDevice;
- (ZDAudioDevice*) BuildInOutputDevice;
- (BOOL)           ContainNameOfDevice:(NSString*)name;
@end

