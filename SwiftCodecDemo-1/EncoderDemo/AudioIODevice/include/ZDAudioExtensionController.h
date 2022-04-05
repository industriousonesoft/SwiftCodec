//
//  ZDAudioExtensionManager.h
//  ZDAudioManagerDemo
//
//  Created by Georgy on 21/12/2016.
//  Copyright © 2016 YuanDuan. All rights reserved.
//

#import <Foundation/Foundation.h>
/*
 此类用于强制设置系统输出为指定的Device
 */
@interface ZDAudioExtensionController : NSObject
- (BOOL) isRunning;
/*
 如果strUID设备不存在，则返回nil
 */
- (instancetype)initWithDeviceUID:(NSString*)strUID;
- (void) startController;
- (void) stopController;
@end
