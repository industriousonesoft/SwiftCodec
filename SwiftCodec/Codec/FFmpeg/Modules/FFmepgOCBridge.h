//
//  OCBridge.h
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^FFmpegAVLogCallback)(NSString *log);

@interface FFmepgOCBridge: NSObject

+ (int)avPIXFMTRGB32;
+ (int)avErrorEOF;
+ (int)avErrorEagain;
+ (char *)avErr2str:(int)errCode;
+ (int64_t)avNoPTSValue;
+ (int64_t)avTimebase;
+ (void)setAVLog:(FFmpegAVLogCallback)callback;

@end
