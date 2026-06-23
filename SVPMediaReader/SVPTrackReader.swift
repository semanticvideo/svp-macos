import Foundation
import MediaExtension
import AVFoundation
import CoreMedia
import os

final class SVPTrackReader: NSObject, METrackReader {

    private let avAsset: AVURLAsset
    private let avTrack: AVAssetTrack
    private let trackID: CMPersistentTrackID
    private let preloadedSamples: [CMSampleBuffer]
    private var totalDuration: CMTime = .zero
    private var minFrameDuration: CMTime = .invalid
    private var formatDescription: CMFormatDescription?

    init(avAsset: AVURLAsset, avTrack: AVAssetTrack, trackID: CMPersistentTrackID, preloadedSamples: [CMSampleBuffer]) {
        self.avAsset = avAsset
        self.avTrack = avTrack
        self.trackID = trackID
        self.preloadedSamples = preloadedSamples
        super.init()
        svpMEReaderLogger.info("SVPTrackReader init: trackID=\(trackID), mediaType=\(avTrack.mediaType.rawValue, privacy: .public), samples=\(preloadedSamples.count, privacy: .public)")
    }

    private var propertiesLoaded = false

    private func loadTrackProperties() async {
        guard !propertiesLoaded else { return }
        propertiesLoaded = true
        do {
            let minFrameDuration = try await self.avTrack.load(.minFrameDuration)
            let formatDescs = try await self.avTrack.load(.formatDescriptions)
            let timeRange = try await self.avTrack.load(.timeRange)
            self.minFrameDuration = minFrameDuration
            self.totalDuration = timeRange.duration
            if let firstDesc = formatDescs.first {
                self.formatDescription = firstDesc
            }
        } catch {
            svpMEReaderLogger.error("loadTrackProperties error: \(String(describing: error), privacy: .public)")
        }
    }

    func loadTrackInfo(completionHandler: @escaping @Sendable (METrackInfo?, Error?) -> Void) {
        Task {
            do {
                let formatDescs = try await self.avTrack.load(.formatDescriptions)
                let avMediaType = self.avTrack.mediaType
                let cmMediaType: CMMediaType
                if avMediaType == .video {
                    cmMediaType = kCMMediaType_Video
                } else if avMediaType == .audio {
                    cmMediaType = kCMMediaType_Audio
                } else {
                    cmMediaType = 0
                }
                let trackInfo = METrackInfo(__mediaType: cmMediaType, trackID: self.trackID, formatDescriptions: formatDescs as [Any])
                trackInfo.isEnabled = true

                let timeRange = try await self.avTrack.load(.timeRange)
                trackInfo.naturalTimescale = timeRange.duration.timescale

                if avMediaType == .video {
                    let naturalSize = try await self.avTrack.load(.naturalSize)
                    let preferredTransform = try await self.avTrack.load(.preferredTransform)
                    let nominalFrameRate = try await self.avTrack.load(.nominalFrameRate)
                    trackInfo.naturalSize = naturalSize
                    trackInfo.preferredTransform = preferredTransform
                    trackInfo.nominalFrameRate = nominalFrameRate
                    trackInfo.requiresFrameReordering = true
                }

                svpMEReaderLogger.info("loadTrackInfo: trackID=\(self.trackID), mediaType=\(avMediaType.rawValue, privacy: .public), formatDescs=\(formatDescs.count, privacy: .public)")
                completionHandler(trackInfo, nil)
            } catch {
                svpMEReaderLogger.error("loadTrackInfo error: \(String(describing: error), privacy: .public)")
                completionHandler(nil, error)
            }
        }
    }

    private func makeCursor() -> SVPSampleCursorObjC {
        return SVPSampleCursorObjC(
            sampleBuffers: preloadedSamples,
            trackID: trackID,
            minFrameDuration: minFrameDuration,
            formatDescription: formatDescription,
            totalDuration: totalDuration
        )
    }

    func generateSampleCursor(atPresentationTimeStamp presentationTimeStamp: CMTime,
                              completionHandler: @escaping @Sendable ((any MESampleCursor)?, Error?) -> Void) {
        Task {
            await self.loadTrackProperties()
            let cursor = self.makeCursor()
            cursor.seek(toPresentationTimeStamp: presentationTimeStamp)
            completionHandler(cursor, nil)
        }
    }

    func generateSampleCursorAtFirstSampleInDecodeOrder(completionHandler: @escaping @Sendable ((any MESampleCursor)?, Error?) -> Void) {
        Task {
            await self.loadTrackProperties()
            let cursor = self.makeCursor()
            cursor.moveToFirstSampleInDecodeOrder()
            completionHandler(cursor, nil)
        }
    }

    func generateSampleCursorAtLastSampleInDecodeOrder(completionHandler: @escaping @Sendable ((any MESampleCursor)?, Error?) -> Void) {
        Task {
            await self.loadTrackProperties()
            let cursor = self.makeCursor()
            cursor.moveToLastSampleInDecodeOrder()
            completionHandler(cursor, nil)
        }
    }

    func loadUneditedDuration(completionHandler: @escaping @Sendable (CMTime, Error?) -> Void) {
        Task {
            await self.loadTrackProperties()
            completionHandler(self.totalDuration, nil)
        }
    }
}
