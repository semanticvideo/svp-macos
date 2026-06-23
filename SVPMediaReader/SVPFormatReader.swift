import Foundation
import MediaExtension
import AVFoundation
import CoreMedia
import SVPReader
import os

final class SVPFormatReader: NSObject, MEFormatReader {

    private var tempDir: URL?
    private var mediaURL: URL?
    private var avAsset: AVURLAsset?

    init(byteSource: MEByteSource) throws {
        super.init()

        svpMEReaderLogger.info("SVPFormatReader init, fileName: \(byteSource.fileName, privacy: .public), fileLength: \(byteSource.fileLength, privacy: .public)")

        let totalLength = byteSource.fileLength
        guard totalLength > 0 else {
            svpMEReaderLogger.error("ByteSource has zero length")
            throw SVPError.notSVPFile("Empty file")
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-me-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let svpTempURL = dir.appendingPathComponent("source.svp")

        let svpData = try SVPFormatReader.readAllData(from: byteSource, length: totalLength)
        try svpData.write(to: svpTempURL)

        svpMEReaderLogger.info("Wrote \(svpData.count, privacy: .public) bytes to temp SVP file")

        let reader = try SVPReader(url: svpTempURL)
        try reader.validateSVP()

        let manifest = try? reader.readManifest()
        svpMEReaderLogger.info("SVP manifest: version=\(manifest?.svpVersion ?? "?", privacy: .public), package=\(manifest?.packageID ?? "?", privacy: .public)")

        let mediaInfo = try reader.locatePrimaryMediaAsset()
        svpMEReaderLogger.info("Primary media: \(mediaInfo.mediaPath, privacy: .public), ext=\(mediaInfo.fileExtension, privacy: .public), size=\(mediaInfo.uncompressedSize, privacy: .public)")

        let destURL = dir.appendingPathComponent(mediaInfo.mediaFileName)
        let mediaData = try reader.readMediaData(mediaInfo)
        try mediaData.write(to: destURL)

        try? FileManager.default.removeItem(at: svpTempURL)

        self.tempDir = dir
        self.mediaURL = destURL
        self.avAsset = AVURLAsset(url: destURL)

        svpMEReaderLogger.info("SVPFormatReader ready, media at: \(destURL.path, privacy: .public)")
    }

    private static func readAllData(from byteSource: MEByteSource, length: Int64) throws -> Data {
        let chunkSize: Int = 1_048_576
        var data = Data()
        var offset: Int64 = 0
        let total = length

        while offset < total {
            let remaining = total - offset
            let toRead = Int(min(Int64(chunkSize), remaining))

            let chunk = try readChunkSync(from: byteSource, offset: offset, length: toRead)
            if chunk.isEmpty { break }
            data.append(chunk)
            offset += Int64(chunk.count)
        }

        return data
    }

    private static func readChunkSync(from byteSource: MEByteSource, offset: Int64, length: Int) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: Error?

        byteSource.read(length: length, from: offset) { data, error in
            resultData = data
            resultError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let error = resultError {
            throw error
        }
        return resultData ?? Data()
    }

    func loadFileInfo(completionHandler: @escaping @Sendable (MEFileInfo?, Error?) -> Void) {
        Task {
            guard let avAsset = self.avAsset else {
                completionHandler(nil, SVPError.ioError("No AV asset"))
                return
            }

            do {
                let durationVar = try await avAsset.load(.duration)
                let info = MEFileInfo()
                info.duration = durationVar
                info.fragmentsStatus = .couldNotContainFragments

                svpMEReaderLogger.info("loadFileInfo: duration=\(CMTimeGetSeconds(durationVar), privacy: .public)s")
                completionHandler(info, nil)
            } catch {
                svpMEReaderLogger.error("loadFileInfo error: \(String(describing: error), privacy: .public)")
                completionHandler(nil, error)
            }
        }
    }

    func loadMetadata(completionHandler: @escaping @Sendable ([AVMetadataItem]?, Error?) -> Void) {
        Task {
            guard let avAsset = self.avAsset else {
                completionHandler(nil, SVPError.ioError("No AV asset"))
                return
            }

            do {
                let metadata = try await avAsset.load(.commonMetadata)
                svpMEReaderLogger.info("loadMetadata: \(metadata.count, privacy: .public) items")
                completionHandler(metadata, nil)
            } catch {
                svpMEReaderLogger.error("loadMetadata error: \(String(describing: error), privacy: .public)")
                completionHandler(nil, error)
            }
        }
    }

    func loadTrackReaders(completionHandler: @escaping @Sendable ([any METrackReader]?, Error?) -> Void) {
        Task {
            guard let avAsset = self.avAsset else {
                completionHandler(nil, SVPError.ioError("No AV asset"))
                return
            }

            do {
                let videoTracks = try await avAsset.loadTracks(withMediaType: .video)
                let audioTracks = try await avAsset.loadTracks(withMediaType: .audio)

                // Filter to only enabled tracks to prevent disabled audio tracks
                // (e.g. secondary spatial/ambisonic tracks on iPhone video) from
                // being played simultaneously, which causes a phase doubling effect.
                // If isEnabled cannot be loaded for a track, default to including it.
                var enabledVideoTracks: [AVAssetTrack] = []
                for track in videoTracks {
                    var isEnabled = true
                    do {
                        isEnabled = try await track.load(.isEnabled)
                    } catch {
                        svpMEReaderLogger.warning("Failed to load isEnabled for video track, defaulting to enabled: \(String(describing: error), privacy: .public)")
                    }
                    if isEnabled { enabledVideoTracks.append(track) }
                }

                var enabledAudioTracks: [AVAssetTrack] = []
                for track in audioTracks {
                    var isEnabled = true
                    do {
                        isEnabled = try await track.load(.isEnabled)
                    } catch {
                        svpMEReaderLogger.warning("Failed to load isEnabled for audio track, defaulting to enabled: \(String(describing: error), privacy: .public)")
                    }
                    if isEnabled { enabledAudioTracks.append(track) }
                }

                // Fallback: if no enabled tracks of a type, use all tracks of that type
                // to avoid silent playback for edge-case files with incorrect flags.
                if enabledVideoTracks.isEmpty && !videoTracks.isEmpty {
                    enabledVideoTracks = videoTracks
                }
                if enabledAudioTracks.isEmpty && !audioTracks.isEmpty {
                    enabledAudioTracks = audioTracks
                }

                let tracks = enabledVideoTracks + enabledAudioTracks

                // Pre-read samples for each track using ObjC helper (AVAssetReader throws
                // ObjC exceptions that can't be caught from Swift in MediaExtension sandbox)
                var samplesByTrack: [Int: [CMSampleBuffer]] = [:]

                for (index, track) in tracks.enumerated() {
                    var readError: NSError?
                    let nsSamples = SVPReadAllSampleBuffers(avAsset, track, &readError)
                    if let readError {
                        svpMEReaderLogger.error("SVPReadAllSampleBuffers failed for track \(index + 1): \(readError.localizedDescription, privacy: .public)")
                        samplesByTrack[index] = []
                    } else {
                        let samples = (nsSamples as? [CMSampleBuffer]) ?? []
                        samplesByTrack[index] = samples
                        svpMEReaderLogger.info("Preloaded \(samples.count, privacy: .public) samples for track \(index + 1, privacy: .public)")
                    }
                }

                var trackReaders: [any METrackReader] = []
                for (index, track) in tracks.enumerated() {
                    let samples = samplesByTrack[index] ?? []
                    let trackReader = SVPTrackReader(avAsset: avAsset, avTrack: track, trackID: CMPersistentTrackID(index + 1), preloadedSamples: samples)
                    trackReaders.append(trackReader)
                }

                svpMEReaderLogger.info("loadTrackReaders: \(trackReaders.count, privacy: .public) tracks")
                completionHandler(trackReaders, nil)
            } catch {
                svpMEReaderLogger.error("loadTrackReaders error: \(String(describing: error), privacy: .public)")
                completionHandler(nil, error)
            }
        }
    }

    deinit {
        if let tempDir {
            SVPReader.cleanupMaterializedMedia(at: tempDir)
        }
    }
}
