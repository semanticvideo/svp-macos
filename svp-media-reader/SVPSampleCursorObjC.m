#import "SVPSampleCursorObjC.h"
#import <os/log.h>
#import <AVFoundation/AVFoundation.h>

BOOL svpObjCTry(void(NS_NOESCAPE ^block)(void), NSError **error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:exception.name ?: @"ObjCException"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown ObjC exception"}];
        }
        return NO;
    }
}

static os_log_t sCursorLog(void) {
    static os_log_t log = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.cueit.svp-system-support", "MediaExtension");
    });
    return log;
}

NSArray *SVPReadAllSampleBuffers(AVURLAsset *asset, AVAssetTrack *track, NSError **error) {
    @try {
        NSError *readerError = nil;
        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&readerError];
        if (readerError) {
            if (error) *error = readerError;
            return nil;
        }

        AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:nil];
        [reader addOutput:output];

        if (![reader startReading]) {
            if (error) *error = reader.error;
            return nil;
        }

        NSMutableArray *samples = [[NSMutableArray alloc] init];
        while (true) {
            CMSampleBufferRef sb = [output copyNextSampleBuffer];
            if (sb == NULL) break;

            // Skip empty sample buffers (first one can be a placeholder)
            CMBlockBufferRef checkBB = CMSampleBufferGetDataBuffer(sb);
            if (checkBB == NULL || CMSampleBufferGetNumSamples(sb) == 0) {
                CFRelease(sb);
                continue;
            }

            CMItemCount numSamples = CMSampleBufferGetNumSamples(sb);
            if (numSamples > 1) {
                // Split multi-sample buffer into individual single-sample buffers
                CMFormatDescriptionRef fd = CMSampleBufferGetFormatDescription(sb);
                CMBlockBufferRef dataBB = CMSampleBufferGetDataBuffer(sb);

                // Calculate sample offsets within the block buffer
                size_t currentOffset = 0;

                for (CMItemCount i = 0; i < numSamples; i++) {
                    CMSampleTimingInfo timing;
                    OSStatus timingErr = CMSampleBufferGetSampleTimingInfo(sb, i, &timing);
                    if (timingErr != noErr) continue;

                    size_t sampleSize = CMSampleBufferGetSampleSize(sb, i);

                    // Create a block buffer reference to just this sample's data
                    CMBlockBufferRef singleBB = NULL;
                    OSStatus bbErr = CMBlockBufferCreateWithBufferReference(
                        kCFAllocatorDefault, dataBB, currentOffset, sampleSize, 0, &singleBB);
                    if (bbErr != noErr || singleBB == NULL) {
                        currentOffset += sampleSize;
                        continue;
                    }

                    // Create single-sample CMSampleBuffer
                    CMSampleBufferRef singleSB = NULL;
                    OSStatus sbErr = CMSampleBufferCreateReady(
                        kCFAllocatorDefault, singleBB, fd, 1, 1,
                        &timing, 1, &sampleSize, &singleSB);
                    CFRelease(singleBB);

                    if (sbErr == noErr && singleSB != NULL) {
                        [samples addObject:(__bridge_transfer id)singleSB];
                    } else if (singleSB != NULL) {
                        CFRelease(singleSB);
                    }

                    currentOffset += sampleSize;
                }
                CFRelease(sb);
            } else {
                // Single sample buffer - retain directly
                CFRetain(sb);
                [samples addObject:(__bridge_transfer id)sb];
                CFRelease(sb);
            }
        }

        // Keep reader alive just in case
        static NSMutableArray *sKeepAliveReaders = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sKeepAliveReaders = [[NSMutableArray alloc] init];
        });
        [sKeepAliveReaders addObject:reader];

        return samples;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:exception.name ?: @"ObjCException"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown ObjC exception"}];
        }
        return nil;
    }
}

@interface SVPSampleCursorObjC ()
// Shared pre-read sample buffers (retained)
@property (nonatomic, strong) NSArray *sampleBuffers;
@property (nonatomic, assign) NSUInteger sampleIndex;
@property (nonatomic, assign) CMPersistentTrackID trackID;
@property (nonatomic, assign) CMTime minFrameDuration;
@property (nonatomic, assign) CMTime totalDuration;

// Required protocol properties (readwrite for internal use)
@property (nonatomic, readwrite) CMTime presentationTimeStamp;
@property (nonatomic, readwrite) CMTime decodeTimeStamp;
@property (nonatomic, readwrite) CMTime currentSampleDuration;
@property (nonatomic, readwrite, nullable) __attribute__((NSObject)) CMFormatDescriptionRef currentSampleFormatDescription;

// Optional protocol properties
@property (nonatomic, readwrite) AVSampleCursorSyncInfo syncInfo;
@property (nonatomic, readwrite) CMTime decodeTimeOfLastSampleReachableByForwardSteppingThatIsAlreadyLoadedByByteSource;
@end

@implementation SVPSampleCursorObjC

#pragma mark - Init

- (instancetype)initWithSampleBuffers:(NSArray *)sampleBuffers
                            trackID:(CMPersistentTrackID)trackID
                    minFrameDuration:(CMTime)minFrameDuration
                   formatDescription:(CMFormatDescriptionRef _Nullable)formatDesc
                       totalDuration:(CMTime)totalDuration
{
    self = [super init];
    if (self) {
        _sampleBuffers = sampleBuffers;
        _trackID = trackID;
        _minFrameDuration = minFrameDuration;
        _totalDuration = totalDuration;
        _sampleIndex = 0;
        _currentSampleFormatDescription = NULL;

        if (formatDesc != NULL) {
            _currentSampleFormatDescription = (CMFormatDescriptionRef)CFRetain(formatDesc);
        }

        _decodeTimeOfLastSampleReachableByForwardSteppingThatIsAlreadyLoadedByByteSource = totalDuration;

        // Populate properties from first sample (like FFMPEG does)
        [self updateStateFromCurrentSample];

        os_log_info(sCursorLog(), "SVPSampleCursorObjC init: trackID=%d, sampleCount=%lu, hasFormatDesc=%d",
                    trackID, (unsigned long)sampleBuffers.count, formatDesc != NULL);
    }
    return self;
}

- (void)dealloc
{
    if (_currentSampleFormatDescription != NULL) {
        CFRelease(_currentSampleFormatDescription);
        _currentSampleFormatDescription = NULL;
    }
    _sampleBuffers = nil;
}

#pragma mark - State Update

- (void)updateStateFromCurrentSample
{
    if (self.sampleIndex >= self.sampleBuffers.count) {
        self.presentationTimeStamp = self.totalDuration;
        self.decodeTimeStamp = self.totalDuration;
        self.currentSampleDuration = kCMTimeInvalid;
        return;
    }

    CMSampleBufferRef sb = (__bridge CMSampleBufferRef)self.sampleBuffers[self.sampleIndex];

    self.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sb);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sb);
    if (CMTIME_IS_INVALID(dts)) {
        dts = self.presentationTimeStamp;
    }
    self.decodeTimeStamp = dts;
    CMTime dur = CMSampleBufferGetDuration(sb);
    if (CMTIME_IS_INVALID(dur) || CMTimeCompare(dur, kCMTimeZero) == 0) {
        dur = self.minFrameDuration;
    }
    self.currentSampleDuration = dur;

    // Update format description from sample if we don't have one
    if (self.currentSampleFormatDescription == NULL) {
        CMFormatDescriptionRef fd = CMSampleBufferGetFormatDescription(sb);
        if (fd) {
            self.currentSampleFormatDescription = (CMFormatDescriptionRef)CFRetain(fd);
        }
    }

    // Basic sync info — keyframes have full sync
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sb, 0);
    BOOL isSync = YES;
    if (attachments != NULL && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef dict = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFBooleanRef notSync = (CFBooleanRef)CFDictionaryGetValue(dict, kCMSampleAttachmentKey_NotSync);
        if (notSync != NULL) {
            isSync = !CFBooleanGetValue(notSync);
        }
    }
    AVSampleCursorSyncInfo sync = {0};
    sync.sampleIsFullSync = isSync;
    sync.sampleIsPartialSync = NO;
    sync.sampleIsDroppable = NO;
    self.syncInfo = sync;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    SVPSampleCursorObjC *copy = [[SVPSampleCursorObjC alloc] initWithSampleBuffers:self.sampleBuffers
                                                                           trackID:self.trackID
                                                                   minFrameDuration:self.minFrameDuration
                                                                  formatDescription:self.currentSampleFormatDescription
                                                                      totalDuration:self.totalDuration];
    copy.sampleIndex = self.sampleIndex;
    [copy updateStateFromCurrentSample];
    return copy;
}

#pragma mark - Sample positioning

- (void)seekToPresentationTimeStamp:(CMTime)pts
{
    // Find the sample with PTS closest to the target
    NSUInteger bestIndex = 0;
    CMTime bestDelta = CMTimeMake(INT64_MAX, 1);

    for (NSUInteger i = 0; i < self.sampleBuffers.count; i++) {
        CMSampleBufferRef sb = (__bridge CMSampleBufferRef)self.sampleBuffers[i];
        CMTime samplePTS = CMSampleBufferGetPresentationTimeStamp(sb);
        CMTime delta = CMTimeSubtract(samplePTS, pts);
        if (CMTimeCompare(delta, kCMTimeZero) >= 0) {
            // First sample at or after target
            bestIndex = i;
            break;
        }
        // Track closest before target
        CMTime absDelta = CMTimeMake(llabs(delta.value), delta.timescale);
        if (CMTimeCompare(absDelta, bestDelta) < 0) {
            bestDelta = absDelta;
            bestIndex = i;
        }
    }

    self.sampleIndex = bestIndex;
    [self updateStateFromCurrentSample];
}

- (void)moveToFirstSampleInDecodeOrder
{
    self.sampleIndex = 0;
    [self updateStateFromCurrentSample];
}

- (void)moveToLastSampleInDecodeOrder
{
    self.sampleIndex = self.sampleBuffers.count > 0 ? self.sampleBuffers.count - 1 : 0;
    [self updateStateFromCurrentSample];
}

#pragma mark - Stepping (actually moves through real samples)

- (void)stepInDecodeOrderByCount:(int64_t)stepCount
               completionHandler:(void (^)(int64_t, NSError * _Nullable))completionHandler
{
    int64_t oldIndex = (int64_t)self.sampleIndex;
    int64_t newIndex = oldIndex + stepCount;
    if (newIndex < 0) newIndex = 0;
    if ((NSUInteger)newIndex >= self.sampleBuffers.count) {
        newIndex = (int64_t)self.sampleBuffers.count - 1;
        if (newIndex < 0) newIndex = 0;
    }
    self.sampleIndex = (NSUInteger)newIndex;
    [self updateStateFromCurrentSample];
    int64_t actual = (int64_t)self.sampleIndex - oldIndex;
    completionHandler(actual, nil);
}

- (void)stepInPresentationOrderByCount:(int64_t)stepCount
                     completionHandler:(void (^)(int64_t, NSError * _Nullable))completionHandler
{
    [self stepInDecodeOrderByCount:stepCount completionHandler:completionHandler];
}

- (void)stepByDecodeTime:(CMTime)deltaDecodeTime
        completionHandler:(void (^)(CMTime, BOOL, NSError * _Nullable))completionHandler
{
    CMTime targetDTS = CMTimeAdd(self.decodeTimeStamp, deltaDecodeTime);
    BOOL pinned = NO;

    if (CMTimeCompare(targetDTS, kCMTimeZero) < 0) {
        targetDTS = kCMTimeZero;
        pinned = YES;
    }
    if (CMTimeCompare(targetDTS, self.totalDuration) > 0) {
        targetDTS = self.totalDuration;
        pinned = YES;
    }

    // Find sample with DTS closest to target
    NSUInteger bestIndex = self.sampleIndex;
    CMTime bestDelta = CMTimeMake(INT64_MAX, 1);

    for (NSUInteger i = 0; i < self.sampleBuffers.count; i++) {
        CMSampleBufferRef sb = (__bridge CMSampleBufferRef)self.sampleBuffers[i];
        CMTime sampleDTS = CMSampleBufferGetDecodeTimeStamp(sb);
        if (CMTIME_IS_INVALID(sampleDTS)) sampleDTS = CMSampleBufferGetPresentationTimeStamp(sb);
        CMTime delta = CMTimeSubtract(sampleDTS, targetDTS);
        if (CMTimeCompare(delta, kCMTimeZero) >= 0) {
            bestIndex = i;
            break;
        }
        CMTime absDelta = CMTimeMake(llabs(delta.value), delta.timescale);
        if (CMTimeCompare(absDelta, bestDelta) < 0) {
            bestDelta = absDelta;
            bestIndex = i;
        }
    }

    self.sampleIndex = bestIndex;
    [self updateStateFromCurrentSample];
    completionHandler(self.decodeTimeStamp, pinned, nil);
}

- (void)stepByPresentationTime:(CMTime)deltaPresentationTime
             completionHandler:(void (^)(CMTime, BOOL, NSError * _Nullable))completionHandler
{
    CMTime targetPTS = CMTimeAdd(self.presentationTimeStamp, deltaPresentationTime);
    BOOL pinned = NO;

    if (CMTimeCompare(targetPTS, kCMTimeZero) < 0) {
        targetPTS = kCMTimeZero;
        pinned = YES;
    }
    if (CMTimeCompare(targetPTS, self.totalDuration) > 0) {
        targetPTS = self.totalDuration;
        pinned = YES;
    }

    // Find sample with PTS closest to target
    NSUInteger bestIndex = self.sampleIndex;
    CMTime bestDelta = CMTimeMake(INT64_MAX, 1);

    for (NSUInteger i = 0; i < self.sampleBuffers.count; i++) {
        CMSampleBufferRef sb = (__bridge CMSampleBufferRef)self.sampleBuffers[i];
        CMTime samplePTS = CMSampleBufferGetPresentationTimeStamp(sb);
        CMTime delta = CMTimeSubtract(samplePTS, targetPTS);
        if (CMTimeCompare(delta, kCMTimeZero) >= 0) {
            bestIndex = i;
            break;
        }
        CMTime absDelta = CMTimeMake(llabs(delta.value), delta.timescale);
        if (CMTimeCompare(absDelta, bestDelta) < 0) {
            bestDelta = absDelta;
            bestIndex = i;
        }
    }

    self.sampleIndex = bestIndex;
    [self updateStateFromCurrentSample];
    completionHandler(self.presentationTimeStamp, pinned, nil);
}

#pragma mark - Frame reordering (matches FFMPEG pattern)

- (BOOL)samplesWithEarlierDTSsMayHaveLaterPTSsThanCursor:(id<MESampleCursor>)cursor
{
    return YES;
}

- (BOOL)samplesWithLaterDTSsMayHaveEarlierPTSsThanCursor:(id<MESampleCursor>)cursor
{
    return YES;
}

#pragma mark - Load sample buffer

- (void)loadSampleBufferContainingSamplesToEndCursor:(id<MESampleCursor> _Nullable)endSampleCursor
                                   completionHandler:(void (^)(CMSampleBufferRef _Nullable, NSError * _Nullable))completionHandler
{
    if (self.sampleIndex >= self.sampleBuffers.count) {
        os_log_error(sCursorLog(), "loadSampleBuffer: no more samples");
        completionHandler(NULL, [NSError errorWithDomain:@"com.cueit.svp" code:MEErrorNoSamples userInfo:nil]);
        return;
    }

    // All buffers are single-sample, so just return the current one.
    // QuickTime will step the cursor and call again for the next sample.
    CMSampleBufferRef originalSB = (__bridge CMSampleBufferRef)self.sampleBuffers[self.sampleIndex];
    CFRetain(originalSB);
    completionHandler(originalSB, nil);
    CFRelease(originalSB);
}

@end
