import Foundation
import MediaExtension
import AVFoundation
import CoreMedia
import SVPReader
import os
import Darwin

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class SVPFormatReader: NSObject, MEFormatReader {

    private let byteSource: MEByteSource
    private let totalLength: Int64
    private var tempDir: URL?
    private var mediaURL: URL?
    private var avAsset: AVURLAsset?
    private var sampleTablesByMediaType: [AVMediaType: [[SVPSampleRecord]]] = [:]
    private let materializationLock = NSLock()

    init(byteSource: MEByteSource) throws {
        self.byteSource = byteSource
        self.totalLength = byteSource.fileLength
        super.init()

        svpMEReaderLogger.info("SVPFormatReader init, fileName: \(byteSource.fileName, privacy: .public), fileLength: \(byteSource.fileLength, privacy: .public)")

        guard self.totalLength > 0 else {
            svpMEReaderLogger.error("ByteSource has zero length")
            throw SVPError.notSVPFile("Empty file")
        }

        svpMEReaderLogger.info("SVPFormatReader initialized without materializing media")
    }

    private func loadAssetIfNeeded() throws -> AVURLAsset {
        materializationLock.lock()
        defer {
            materializationLock.unlock()
        }

        if let avAsset {
            return avAsset
        }

        let interprocessLock = try SVPFormatReader.InterprocessMaterializationLock()
        defer {
            interprocessLock.unlock()
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-me-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let svpTempURL = dir.appendingPathComponent("source.svp")

        let bytesWritten = try SVPFormatReader.writeAllData(from: byteSource, length: totalLength, to: svpTempURL)

        svpMEReaderLogger.info("Wrote \(bytesWritten, privacy: .public) bytes to temp SVP file")

        let reader = try SVPReader(url: svpTempURL)
        try reader.validateSVP()

        let manifest = try? reader.readManifest()
        svpMEReaderLogger.info("SVP manifest: version=\(manifest?.svpVersion ?? "?", privacy: .public), package=\(manifest?.packageID ?? "?", privacy: .public)")

        let mediaInfo = try reader.locatePrimaryMediaAsset()
        svpMEReaderLogger.info("Primary media: \(mediaInfo.mediaPath, privacy: .public), ext=\(mediaInfo.fileExtension, privacy: .public), size=\(mediaInfo.uncompressedSize, privacy: .public)")
        let mediaDataOffset = try reader.mediaDataOffset(mediaInfo)

        let destURL = dir.appendingPathComponent("init-\(mediaInfo.mediaFileName)")
        try SVPMP4InitializationSegmentWriter.write(
            from: svpTempURL,
            mediaBaseOffset: mediaDataOffset,
            mediaSize: mediaInfo.uncompressedSize,
            to: destURL
        )

        try? FileManager.default.removeItem(at: svpTempURL)

        self.tempDir = dir
        self.mediaURL = destURL
        let asset = AVURLAsset(url: destURL)
        self.avAsset = asset
        self.sampleTablesByMediaType = try Self.loadSampleTables(from: destURL, mediaDataOffset: mediaDataOffset)

        svpMEReaderLogger.info("SVPFormatReader ready, media at: \(destURL.path, privacy: .public)")
        return asset
    }

    private static func loadSampleTables(from mediaURL: URL, mediaDataOffset: UInt64) throws -> [AVMediaType: [[SVPSampleRecord]]] {
        let parsedTracks = try SVPMP4SampleTableParser(url: mediaURL).parseTracks()
        var tables: [AVMediaType: [[SVPSampleRecord]]] = [:]

        for parsedTrack in parsedTracks {
            let records = parsedTrack.samples.map { sample -> SVPSampleRecord in
                let record = SVPSampleRecord()
                record.offset = mediaDataOffset + sample.offset
                record.size = UInt64(sample.size)
                record.pts = sample.pts
                record.dts = sample.dts
                record.duration = sample.duration
                record.sync = sample.isSync
                return record
            }
            tables[parsedTrack.mediaType, default: []].append(records)
            svpMEReaderLogger.info("Loaded MP4 sample table: mediaType=\(parsedTrack.mediaType.rawValue, privacy: .public), samples=\(records.count, privacy: .public)")
        }

        return tables
    }

    private final class InterprocessMaterializationLock {
        private let fd: Int32

        init() throws {
            let lockURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("svp-media-reader-materialize.lock")
            fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            guard fd >= 0 else {
                throw SVPError.ioError("Cannot open materialization lock")
            }

            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                close(fd)
                throw SVPError.ioError("Another SVPMediaReader process is materializing media")
            }
        }

        func unlock() {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }

    private static func writeAllData(from byteSource: MEByteSource, length: Int64, to destinationURL: URL) throws -> Int64 {
        let chunkSize: Int = 1_048_576
        var offset: Int64 = 0
        let total = length

        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw SVPError.ioError("Cannot create temp SVP file")
        }
        let outputHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? outputHandle.close()
        }

        while offset < total {
            let remaining = total - offset
            let toRead = Int(min(Int64(chunkSize), remaining))

            let chunk = try readChunkSync(from: byteSource, offset: offset, length: toRead)
            if chunk.isEmpty {
                throw SVPError.ioError("Unexpected EOF while reading SVP byte source")
            }
            outputHandle.write(chunk)
            offset += Int64(chunk.count)
        }

        return offset
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
            do {
                let avAsset = try self.loadAssetIfNeeded()
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
            do {
                let avAsset = try self.loadAssetIfNeeded()
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
            do {
                let avAsset = try self.loadAssetIfNeeded()
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

                var trackReaders: [any METrackReader] = []
                var mediaTypeIndexes: [AVMediaType: Int] = [:]
                for (index, track) in tracks.enumerated() {
                    let mediaType = track.mediaType
                    let mediaTypeIndex = mediaTypeIndexes[mediaType, default: 0]
                    mediaTypeIndexes[mediaType] = mediaTypeIndex + 1
                    let sampleRecords = self.sampleTablesByMediaType[mediaType]?[safe: mediaTypeIndex] ?? []
                    let trackReader = SVPTrackReader(
                        avAsset: avAsset,
                        avTrack: track,
                        byteSource: self.byteSource,
                        sampleRecords: sampleRecords,
                        trackID: CMPersistentTrackID(index + 1)
                    )
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
