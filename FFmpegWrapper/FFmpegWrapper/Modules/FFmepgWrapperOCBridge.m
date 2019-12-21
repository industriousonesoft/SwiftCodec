//
// OCBridge.m
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 zenet. All rights reserved.
//

#import "FFmepgWrapperOCBridge.h"
#import "libavutil/avutil.h"
#import "libavutil/imgutils.h"
#import "libavcodec/avcodec.h"
#import "libswscale/swscale.h"

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

+ (char *)avErr2str:(int)errCode {
    return av_err2str(errCode);
}

+ (int64_t)avNoPTSValue {
    
    return AV_NOPTS_VALUE;
}

+ (int64_t)avTimebase {
    return AV_TIME_BASE;
}


@end
