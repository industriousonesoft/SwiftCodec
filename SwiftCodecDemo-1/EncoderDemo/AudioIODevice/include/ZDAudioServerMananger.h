//
//  ZDAudioServerMananger.h
//  ZDAudioServerMananger
//
//  Created by Georgy on 9/19/16.
//  Copyright © 2016 YuanDuan. All rights reserved.
//

#import <Foundation/Foundation.h>

//自动管理音频插件数据，如果需要自行处理音频数据，请不要使用此类
@class ZDEqualizer;
typedef NS_ENUM(NSInteger, ZDAudioManagerStatus){
    ZDAM_NA=-1,
    ZDAM_RUNNING=0,
    ZDAM_STOPPED=1
};

@interface ZDAudioServerMananger : NSObject
@property float volume;//0.0-1.0

- (BOOL) isRunning;
- (ZDEqualizer*) equalizer;
- (BOOL) startServerWithInputDeviceName:(NSString*)name;;
- (void) stopServer;

+(ZDAudioServerMananger*) shareManager;
@end
