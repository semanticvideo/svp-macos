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

@interface SVPSampleCursorObjC ()
@property (nonatomic, strong) MEByteSource *byteSource;
@property (nonatomic, strong) NSArray *samples;
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

@implementation SVPSampleRecord
@end

@implementation SVPSampleCursorObjC

#pragma mark - Init

- (instancetype)initWithByteSource:(MEByteSource *)byteSource
                            samples:(NSArray *)samples
                            trackID:(CMPersistentTrackID)trackID
                    minFrameDuration:(CMTime)minFrameDuration
                   formatDescription:(CMFormatDescriptionRef _Nullable)formatDesc
                       totalDuration:(CMTime)totalDuration
{
    self = [super init];
    if (self) {
        _byteSource = byteSource;
        _samples = samples;
        _trackID = trackID;
        _minFrameDuration = minFrameDuration;
        _totalDuration = totalDuration;
        _sampleIndex = 0;
        _currentSampleFormatDescription = NULL;

        if (formatDesc != NULL) {
            _currentSampleFormatDescription = (CMFormatDescriptionRef)CFRetain(formatDesc);
        }

        _decodeTimeOfLastSampleReachableByForwardSteppingThatIsAlreadyLoadedByByteSource = totalDuration;

        [self updateStateFromCurrentSample];

        os_log_info(sCursorLog(), "SVPSampleCursorObjC init: trackID=%d, sampleCount=%lu, hasFormatDesc=%d",
                    trackID, (unsigned long)samples.count, formatDesc != NULL);
    }
    return self;
}

- (void)dealloc
{
    if (_currentSampleFormatDescription != NULL) {
        CFRelease(_currentSampleFormatDescription);
        _currentSampleFormatDescription = NULL;
    }
    _samples = nil;
}

#pragma mark - State Update

- (void)updateStateFromCurrentSample
{
    if (self.sampleIndex >= self.samples.count) {
        self.presentationTimeStamp = self.totalDuration;
        self.decodeTimeStamp = self.totalDuration;
        self.currentSampleDuration = kCMTimeInvalid;
        return;
    }

    SVPSampleRecord *sample = self.samples[self.sampleIndex];

    self.presentationTimeStamp = sample.pts;
    self.decodeTimeStamp = sample.dts;
    self.currentSampleDuration = sample.duration;

    // Basic sync info — keyframes have full sync
    AVSampleCursorSyncInfo sync = {0};
    sync.sampleIsFullSync = sample.sync;
    sync.sampleIsPartialSync = NO;
    sync.sampleIsDroppable = NO;
    self.syncInfo = sync;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    SVPSampleCursorObjC *copy = [[SVPSampleCursorObjC alloc] initWithByteSource:self.byteSource
                                                                        samples:self.samples
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
    NSUInteger bestIndex = 0;
    for (NSUInteger i = 0; i < self.samples.count; i++) {
        SVPSampleRecord *sample = self.samples[i];
        if (CMTimeCompare(sample.pts, pts) <= 0) {
            bestIndex = i;
        } else {
            break;
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
    self.sampleIndex = self.samples.count > 0 ? self.samples.count - 1 : 0;
    [self updateStateFromCurrentSample];
}

#pragma mark - Stepping (actually moves through real samples)

- (void)stepInDecodeOrderByCount:(int64_t)stepCount
               completionHandler:(void (^)(int64_t, NSError * _Nullable))completionHandler
{
    int64_t oldIndex = (int64_t)self.sampleIndex;
    int64_t newIndex = oldIndex + stepCount;
    if (newIndex < 0) newIndex = 0;
    if ((NSUInteger)newIndex >= self.samples.count) {
        newIndex = (int64_t)self.samples.count - 1;
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

    NSUInteger bestIndex = self.sampleIndex;
    for (NSUInteger i = 0; i < self.samples.count; i++) {
        SVPSampleRecord *sample = self.samples[i];
        if (CMTimeCompare(sample.dts, targetDTS) >= 0) {
            bestIndex = i;
            break;
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

    [self seekToPresentationTimeStamp:targetPTS];
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
    completionHandler(NULL, [NSError errorWithDomain:@"com.cueit.svp" code:MEErrorLocationNotAvailable userInfo:nil]);
}

- (MESampleLocation *)sampleLocationReturningError:(NSError **)error
{
    if (self.sampleIndex >= self.samples.count) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.cueit.svp" code:MEErrorNoSamples userInfo:nil];
        }
        return nil;
    }

    SVPSampleRecord *sample = self.samples[self.sampleIndex];
    AVSampleCursorStorageRange range = { (int64_t)sample.offset, (int64_t)sample.size };
    return [[MESampleLocation alloc] initWithByteSource:self.byteSource sampleLocation:range];
}

@end
