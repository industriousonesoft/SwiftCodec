//
// OCBridge.m
//  FFMpegEncoder
//
//  Created by caowanping on 2019/11/27.
//  Copyright © 2019 industriousonesoft. All rights reserved.
//

#import "FFmepgOCBridge.h"
#import "libavutil/avutil.h"
#import "libavutil/imgutils.h"
#import "libavcodec/avcodec.h"
#import "libswscale/swscale.h"

static FFmpegAVLogCallback avLogCallback = nil;

@implementation FFmepgOCBridge

+ (int)avPIXFMTRGB32 {
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

+ (void)setAVLog:(FFmpegAVLogCallback)callback {
    av_log_set_level(AV_LOG_VERBOSE);
    av_log_set_callback(ffmpeg_log_callback);
    avLogCallback = callback;
}

static void ffmpeg_log_callback(void *ptr, int level, const char *fmt, va_list vl) {
    if (level > av_log_get_level()) {
        return;
    }
    
    char temp[1024];
    vsprintf(temp, fmt, vl);
    size_t len = strlen(temp);
    if (len > 0 && len < 1024&&temp[len - 1] == '\n')
    {
        temp[len - 1] = '\0';
    }

    AVClass* avc = ptr ? *(AVClass **)ptr : NULL;
    const char *module = avc ? avc->item_name(ptr) : "NULL";
//    printf("AVLog: module: %s - info: %s \n", module, temp);
    NSString *log = [[NSString alloc] initWithFormat:@"AVLog: module: %s - info: %s", module, temp];
    avLogCallback(log);
}

@end
