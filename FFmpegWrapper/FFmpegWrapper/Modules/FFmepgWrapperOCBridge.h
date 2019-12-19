//
//  OCBridge.h
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FFmepgWrapperOCBridge : NSObject

+ (int)avPixelFormatRGB32;
+ (int)avErrorEOF;
+ (int)avErrorEagain;
+ (char *)avErr2str:(int)errCode;
+ (int64_t)avNoPTSValue;

@end
