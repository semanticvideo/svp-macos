#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaExtension/MediaExtension.h>

NS_ASSUME_NONNULL_BEGIN

// Helper to catch ObjC exceptions from Swift
BOOL svpObjCTry(void(NS_NOESCAPE ^block)(void), NSError **error);

@interface SVPSampleRecord : NSObject
@property (nonatomic, assign) uint64_t offset;
@property (nonatomic, assign) uint64_t size;
@property (nonatomic, assign) CMTime pts;
@property (nonatomic, assign) CMTime dts;
@property (nonatomic, assign) CMTime duration;
@property (nonatomic, assign) BOOL sync;
@end

@interface SVPSampleCursorObjC : NSObject <MESampleCursor>

- (instancetype)initWithByteSource:(MEByteSource *)byteSource
                            samples:(NSArray *)samples
                            trackID:(CMPersistentTrackID)trackID
                    minFrameDuration:(CMTime)minFrameDuration
                   formatDescription:(CMFormatDescriptionRef _Nullable)formatDesc
                       totalDuration:(CMTime)totalDuration;

- (void)moveToFirstSampleInDecodeOrder;
- (void)moveToLastSampleInDecodeOrder;
- (void)seekToPresentationTimeStamp:(CMTime)pts;

@end

NS_ASSUME_NONNULL_END
