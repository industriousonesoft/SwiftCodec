//
//  ZDAudioDevicePlayThrough.h
//  ZDAudioManagerDemo
//
//  Created by Georgy on 25/08/2017.
//  Copyright © 2017 Yinxiaoqi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>


@protocol ZDAudioDevicePlayThroughDataProcess;

@interface ZDAudioDevicePlayThrough : NSObject
@property id<ZDAudioDevicePlayThroughDataProcess> delegate;
- (id) initWithInputDevice:(AudioObjectID)inputDeviceID outputDevice:(AudioObjectID)outputDeviceID;
- (void)     start;
- (OSStatus) stop;
- (BOOL) isRunning;
@end

@protocol ZDAudioDevicePlayThroughDataProcess <NSObject>
- (void) processInputData:(const AudioBufferList*)inInputData;
@end
