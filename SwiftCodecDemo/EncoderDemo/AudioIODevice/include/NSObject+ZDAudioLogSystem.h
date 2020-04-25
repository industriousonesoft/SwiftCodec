//
//  NSObject+ZDAudioUtility.h
//  ZDAudioManagerDemo
//
//  Created by Georgy on 26/08/2017.
//  Copyright © 2017 Yinxiaoqi. All rights reserved.
//

#import <Foundation/Foundation.h>
typedef enum {
    ZDAudioLogInfo,
    ZDAudioLogWarning,
    ZDAudioLogErro
}ZDAudioManagerLogLevel;
@interface NSObject (ZDAudioLogSystem)
- (void) setZDAudioLogSystemCallBack:(void (*)(int, NSString *))callback;
- (void) logLevel:(int)level message:(NSString *)message, ...;
@end

