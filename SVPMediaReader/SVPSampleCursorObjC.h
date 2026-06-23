#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaExtension/MediaExtension.h>

NS_ASSUME_NONNULL_BEGIN

// Helper to catch ObjC exceptions from Swift
BOOL svpObjCTry(void(NS_NOESCAPE ^block)(void), NSError **error);

// Helper to read all sample buffers from an AVAssetTrack using AVAssetReader
// This must be in ObjC to properly catch ObjC exceptions
NSArray *SVPReadAllSampleBuffers(AVURLAsset *asset, AVAssetTrack *track, NSError **error);

@interface SVPSampleCursorObjC : NSObject <MESampleCursor>

- (instancetype)initWithSampleBuffers:(NSArray *)sampleBuffers
                            trackID:(CMPersistentTrackID)trackID
                    minFrameDuration:(CMTime)minFrameDuration
                   formatDescription:(CMFormatDescriptionRef _Nullable)formatDesc
                       totalDuration:(CMTime)totalDuration;

- (void)moveToFirstSampleInDecodeOrder;
- (void)moveToLastSampleInDecodeOrder;
- (void)seekToPresentationTimeStamp:(CMTime)pts;

@end

NS_ASSUME_NONNULL_END
