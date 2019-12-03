//
// OCBridge.m
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

#import "FFmepgWrapperOCBridge.h"
#import "avutil.h"
#import "imgutils.h"
#import "avcodec.h"
#import "swscale.h"

@implementation FFmepgWrapperOCBridge

+ (int)avPixelFormatRGB32 {
    return AV_PIX_FMT_RGB32;
}

+ (int)avErrorEOF {
    return AVERROR_EOF;
}

+ (int)avErrorEagain {
    return AVERROR(EAGAIN);
}
@end
