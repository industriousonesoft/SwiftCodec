//
//  ZDLocalAudioDefines.h
//  ZDAudioManagerDemo
//
//  Created by Georgy on 19/12/2016.
//  Copyright © 2016 YuanDuan. All rights reserved.
//

#ifndef ZDLocalAudioDefines_h
#define ZDLocalAudioDefines_h

typedef enum{
    PSStopped,
    PSPlaying,
    PSPaused
}PSStatus;

extern NSString* kAudioDevicesChangedNotification;

#endif /* ZDLocalAudioDefines_h */
