//
//  ZDEuqlizer.h
//  WavTap
//
//  Created by Georgy on 8/26/16.
//
//

#import <Foundation/Foundation.h>
//This Class Only handle 'float' 'interleaved' 'packed' PCM data!
typedef enum sZDEqualizerType{
    ZDFloatType,
    ZDUInt8Type,
    ZDInt16Type,
    ZDInt32Type
}ZDEqualizerType;
@interface ZDEqualizer : NSObject
@property ZDEqualizerType format;
@property int sampleRate;
@property int sampleChannel;
@property int bytePerSample;
@property(retain) NSArray* gainValues;//-10db-10db
@property Float32 gainFactor; //-10db-10db

// manual initialize.
- (instancetype) init;//must call initializeEuqalizer.
- (void) initializeEuqalizer;
// auto initialize.
- (instancetype) initWithFormat:(ZDEqualizerType)type sampleRate:(int)rate sampleChannel:(int)channel bytePerSample:(int)bytePS;
//Audio Handle
- (BOOL) processAudio:(void*)inputData inputByte:(int)inputB outputData:(void*)output outputByte:(int)outputB;
- (void) resetGains;
@end
