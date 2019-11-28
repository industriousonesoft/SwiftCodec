//
//  OCBridgingHelper.h
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OCBridgingHelper : NSObject

+ (int)avPixelFormatRGB32;
+ (int)avErrorEOF;
+ (int)avErrorEagain;

@end
