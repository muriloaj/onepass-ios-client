//
//  OPCSVideoConverter.m
//  OnePassCaptureStandard
//
//  Created by Soloshcheva Aleksandra on 27.07.16.
//  Copyright © 2016 Speech Technology Center. All rights reserved.
//

#import "OPCSVideoConverter.h"
#import <AVFoundation/AVFoundation.h>

@interface OPCSVideoConverter()

/**
 The URL of the file to be converted.
 */
@property (nonatomic) NSURL *assetUrl;

/**
 The URL of the converted file.
 */
@property (nonatomic) NSURL *outputUrl;

/**
 Provides services for obtaining video data from the url.
 */
@property (nonatomic, strong) AVAssetReader                       *reader;

/**
  Defines an interface for reading video frames.
 */
@property (nonatomic, strong) AVAssetReaderVideoCompositionOutput *videoOutput;

/**
 Defines an interface for reading audio samples.
 */
@property (nonatomic, strong) AVAssetReaderAudioMixOutput         *audioOutput;

/**
 Provides services for writing media data to a new file.
 */
@property (nonatomic, strong) AVAssetWriter      *writer;

/**
 Defines an interface for adding new media frames.
 */
@property (nonatomic, strong) AVAssetWriterInput *videoInput;

/**
 Defines an interface for adding new audio samples.
 */
@property (nonatomic, strong) AVAssetWriterInput *audioInput;

/**
 The queue on which the block should be invoked.
 */
@property (nonatomic, strong) dispatch_queue_t queue;

/**
 The block which is invoked after export is finished.
 */
@property (nonatomic, strong) void (^completionHandler)(NSError *error);

#warning docs
@property (nonatomic) OPCAvailableOrientation interfaceOrientation;


@end


@interface OPCSVideoConverter(PrivateMethods)

/**
 The video settings for the result file

 @return The video settings
 */
-(NSDictionary *)videoSettings;

/**
 The audio settings for the result file

 @return The audio settings
 */
-(NSDictionary *)audioSettings;

/**
 Creates the AVVideoComposition instance based on the source video file

 @param url  The URL of the file to be converted
 @return The required video composition
 */
-(AVVideoComposition *)videoCompositionWithAssetsURL:(NSURL *)url;

/**
 Invoked when the convertation is finshed
 */
-(void)finish;

/**
 Encodes data from the reader output and transfers to the writer input

 @param output The output
 @param input The input
 @return YES, if data is transfered
 */
- (BOOL)encodeReadySamplesFromOutput:(AVAssetReaderOutput *)output
                             toInput:(AVAssetWriterInput  *)input;

/**
 Creates video converter error

 @return The error
 */
-(NSError *)videoCoverterError;

/**
 Returns the current video size based on the device orientation

 @return The size of video
 */
-(CGSize)videoSize;

@end

@implementation OPCSVideoConverter

-(id)initWithAssetURL:(NSURL *)url toOutputURL:(NSURL *)outputURL {
    self = [super init];
    
    if (self) {
        _assetUrl  = url;
        _outputUrl = outputURL;
    }

    return self;
}

- (void)exportAsynchronouslyWithCompletionHandler:(void (^)(NSError *error))handler {

    NSParameterAssert(handler != nil);
    self.completionHandler = handler;
    
    AVURLAsset *video = [[AVURLAsset alloc] initWithURL:self.assetUrl options:nil];
    
    NSError *error;
    self.reader = [[AVAssetReader alloc] initWithAsset:video error:&error];
    if (error) {
        handler(error);
        return;
    }
    
    [NSFileManager.defaultManager removeItemAtURL:self.outputUrl error:&error];
    if (error) {
        NSLog(@"%@",error);
    }
    
    self.writer = [AVAssetWriter assetWriterWithURL:self.outputUrl fileType:AVFileTypeQuickTimeMovie error:&error];
    if (error) {
        handler(error);
        return;
    }
    
    self.reader.timeRange = CMTimeRangeMake(kCMTimeZero, video.duration);
    self.writer.shouldOptimizeForNetworkUse = YES;
    
    //processing video
    NSArray *videoTracks = [video tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count > 0) {
        self.videoOutput = [AVAssetReaderVideoCompositionOutput assetReaderVideoCompositionOutputWithVideoTracks:videoTracks videoSettings:nil];
        self.videoOutput.alwaysCopiesSampleData = NO;

        self.videoOutput.videoComposition = [self videoCompositionWithAssetsURL:self.assetUrl];

        if ([self.reader canAddOutput:self.videoOutput]) {
            [self.reader addOutput:self.videoOutput];
        } else {
            handler(self.videoCoverterError);
            return;
        }
        
        // Video input
        self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:self.videoSettings];
        self.videoInput.expectsMediaDataInRealTime = NO;
        if ([self.writer canAddInput:self.videoInput]) {
            [self.writer addInput:self.videoInput];
        } else {
            handler(self.videoCoverterError);
            return;
        }
    }
    
    //Audio output
    NSArray *audioTracks = [video tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count > 0) {
        self.audioOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:audioTracks audioSettings:nil];
        self.audioOutput.alwaysCopiesSampleData = NO;
        if ([self.reader canAddOutput:self.audioOutput]) {
            [self.reader addOutput:self.audioOutput];
        } else {
            handler(self.videoCoverterError);
            return;
        }
    } else {
        self.audioOutput = nil;
    }
    
    // Audio input
    if (self.audioOutput) {
        self.audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:self.audioSettings];
        self.audioInput.expectsMediaDataInRealTime = NO;
        if ([self.writer canAddInput:self.audioInput]) {
            [self.writer addInput:self.audioInput];
        } else {
            handler(self.videoCoverterError);
            return;
        }
    }
    
    [self.writer startWriting];
    [self.reader startReading];
    [self.writer startSessionAtSourceTime:kCMTimeZero];
    
    __block BOOL videoCompleted = NO;
    __block BOOL audioCompleted = NO;
    __weak typeof(self) weakself = self;
    self.queue = dispatch_queue_create("VideoQueue", DISPATCH_QUEUE_SERIAL);
    if (videoTracks.count > 0) {
        [self.videoInput requestMediaDataWhenReadyOnQueue:self.queue usingBlock:^ {
             if (![weakself encodeReadySamplesFromOutput:weakself.videoOutput toInput:weakself.videoInput]) {
                 @synchronized(weakself) {
                     videoCompleted = YES;
                     if (audioCompleted) {
                         [weakself finish];
                     }
                 }
             }
         }];
    } else {
        videoCompleted = YES;
    }
    
    if (!self.audioOutput) {
        audioCompleted = YES;
    } else {
        [self.audioInput requestMediaDataWhenReadyOnQueue:self.queue usingBlock:^{
             if (![weakself encodeReadySamplesFromOutput:weakself.audioOutput toInput:weakself.audioInput]) {
                 @synchronized(weakself) {
                     audioCompleted = YES;
                     if (videoCompleted) {
                         [weakself finish];
                     }
                 }
             }
        }];
    }
}



-(BOOL)isPortraitOrientation{
    return (self.interfaceOrientation==OPCAvailableOrientationUp);
}

@end


@implementation OPCSVideoConverter(PrivateMethods)

-(NSError *)videoCoverterError {
    return [NSError errorWithDomain:@"com.onepass.captureresource"
                               code:400
                           userInfo:@{ NSLocalizedDescriptionKey: @"Video converter error"}];
}

-(NSDictionary *)videoSettings {
    return @{
             AVVideoCodecKey: AVVideoCodecH264,
             AVVideoWidthKey: !self.isPortraitOrientation ? @320 : @240,
             AVVideoHeightKey: !self.isPortraitOrientation ? @240 : @320,
             AVVideoCompressionPropertiesKey: @{
                     AVVideoAverageBitRateKey: @100000,
                     AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
                     }
             };
}

-(NSDictionary *)audioSettings {
    return @{
             AVFormatIDKey: @(kAudioFormatLinearPCM),
             AVNumberOfChannelsKey: @1,
             AVSampleRateKey: @(11025.0),
             AVLinearPCMBitDepthKey:@16,
             AVLinearPCMIsFloatKey:@(NO),
             AVLinearPCMIsBigEndianKey:@(NO),
             AVLinearPCMIsNonInterleaved:@(NO),
             AVChannelLayoutKey:NSData.data
             };
}

-(AVVideoComposition *)videoCompositionWithAssetsURL:(NSURL *)url {
    
    AVURLAsset *video = [[AVURLAsset alloc] initWithURL:url
                                                options:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], AVURLAssetPreferPreciseDurationAndTimingKey, nil]];
    CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, video.duration);
    
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:0];
    NSArray *videoAssetTracks = [video tracksWithMediaType:AVMediaTypeVideo];
    
    AVAssetTrack *videoAssetTrack = ([videoAssetTracks count] > 0 ? [videoAssetTracks objectAtIndex:0] : nil);
    NSError *error;
    [videoTrack insertTimeRange:timeRange ofTrack:videoAssetTrack atTime:kCMTimeZero error:&error];
    
    AVMutableVideoCompositionLayerInstruction *to = [AVMutableVideoCompositionLayerInstruction
                                                     videoCompositionLayerInstructionWithAssetTrack:videoAssetTrack];
#warning MIRRORED
    [to setTransform:CGAffineTransformTranslate( videoAssetTrack.preferredTransform, 0, 0)
              atTime:kCMTimeZero];
    
    // Video Compostion
    AVMutableVideoCompositionInstruction *transition = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
//    transition.backgroundColor = CIColor.clearColor.CGColor;
    transition.timeRange = timeRange;
    transition.layerInstructions = [NSArray arrayWithObjects:to, nil];
    
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.instructions = [NSArray arrayWithObjects:transition,  nil];
    videoComposition.frameDuration = CMTimeMake(1, 30);
    videoComposition.renderSize = self.videoSize;
    return videoComposition;
}

- (BOOL)encodeReadySamplesFromOutput:(AVAssetReaderOutput *)output toInput:(AVAssetWriterInput *)input {
    while (input.isReadyForMoreMediaData) {
        CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
        if (sampleBuffer) {
            BOOL handled = NO;
            BOOL error = NO;
            
            if (self.reader.status != AVAssetReaderStatusReading || self.writer.status != AVAssetWriterStatusWriting) {
                handled = YES;
                error = YES;
            }
            
            if (!handled && ![input appendSampleBuffer:sampleBuffer]) {
                error = YES;
            }

            CFRelease(sampleBuffer);
            
            if (error) {
                return NO;
            }
        } else {
            [input markAsFinished];
            return NO;
        }
    }
    
    return YES;
}

- (void)finish {
    if (self.reader.status == AVAssetReaderStatusCancelled ||
        self.writer.status == AVAssetWriterStatusCancelled) {
        return;
    }
    
    if (self.writer.status == AVAssetWriterStatusFailed) {
        [self complete];
    } else {
        if (self.reader.status == AVAssetReaderStatusFailed) {
            [self.writer cancelWriting];
            [self complete];
        } else {
            [self.writer finishWritingWithCompletionHandler:^{
                 [self complete];
             }];
        }
    }
}

- (void)complete{
    
    if (self.writer.status == AVAssetWriterStatusFailed ||
        self.writer.status == AVAssetWriterStatusCancelled) {
        
        [NSFileManager.defaultManager removeItemAtURL:self.outputUrl error:nil];

        self.completionHandler(self.videoCoverterError);
        return;
    }
    
    if (self.completionHandler) {
        self.completionHandler(nil);
        self.completionHandler = nil;
    }
}

-(CGSize)videoSize{
    return !self.isPortraitOrientation ? CGSizeMake(640, 480) : CGSizeMake(480, 640);
}

@end
