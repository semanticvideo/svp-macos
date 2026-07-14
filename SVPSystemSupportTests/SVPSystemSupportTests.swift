//
//  SVPSystemSupportTests.swift
//  SVPSystemSupportTests
//
//  Created by Dom Esposito on 6/21/26.
//

import XCTest
import SVPReader
@testable import SVPSystemSupport

final class SVPSystemSupportTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testMediaReaderKeepsProcessWideMaterializationThrottle() throws {
        let source = try readSource("SVPMediaReader/SVPFormatReader.swift")

        XCTAssertTrue(source.contains("InterprocessMaterializationLock"))
        XCTAssertTrue(source.contains("svp-media-reader-materialize.lock"))
        XCTAssertTrue(source.contains("LOCK_EX | LOCK_NB"))
        XCTAssertTrue(source.contains("Another SVPMediaReader process is materializing media"))
    }

    func testMediaReaderDoesNotUseEagerSampleBufferLoading() throws {
        let formatReader = try readSource("SVPMediaReader/SVPFormatReader.swift")
        let cursorHeader = try readSource("SVPMediaReader/SVPSampleCursorObjC.h")
        let cursorImplementation = try readSource("SVPMediaReader/SVPSampleCursorObjC.m")

        XCTAssertFalse(formatReader.contains("SVPReadAllSampleBuffers"))
        XCTAssertFalse(cursorHeader.contains("SVPReadAllSampleBuffers"))
        XCTAssertFalse(cursorImplementation.contains("copyNextSampleBuffer"))
        XCTAssertFalse(cursorImplementation.contains("AVAssetReaderTrackOutput"))
        XCTAssertTrue(cursorImplementation.contains("sampleLocationReturningError"))
        XCTAssertTrue(cursorImplementation.contains("MESampleLocation"))
    }

    func testMediaReaderInitializesFromMP4MetadataInsteadOfFullMediaData() throws {
        let formatReader = try readSource("SVPMediaReader/SVPFormatReader.swift")
        let initWriter = try readSource("SVPMediaReader/SVPMP4InitializationSegmentWriter.swift")
        let sampleTable = try readSource("SVPMediaReader/SVPMP4SampleTable.swift")

        XCTAssertTrue(formatReader.contains("SVPMP4InitializationSegmentWriter.write"))
        XCTAssertTrue(formatReader.contains("mediaDataOffset"))
        XCTAssertTrue(formatReader.contains("SVPMP4SampleTableParser"))
        XCTAssertFalse(formatReader.contains("reader.readMediaData"))

        XCTAssertTrue(initWriter.contains("box.type == \"ftyp\" || box.type == \"moov\""))
        XCTAssertFalse(initWriter.contains("box.type == \"mdat\""))
        XCTAssertTrue(sampleTable.contains("readMovieBox"))
        XCTAssertTrue(sampleTable.contains("parseTracks"))
    }

    func testMediaReaderCleansMaterializationDirectoryWhenSetupFails() throws {
        let formatReader = try readSource("SVPMediaReader/SVPFormatReader.swift")
        let initWriter = try readSource("SVPMediaReader/SVPMP4InitializationSegmentWriter.swift")

        XCTAssertTrue(formatReader.contains("self.tempDir = dir"))
        XCTAssertTrue(formatReader.contains("var setupSucceeded = false"))
        XCTAssertTrue(formatReader.contains("if !setupSucceeded"))
        XCTAssertTrue(formatReader.contains("SVPReader.cleanupMaterializedMedia(at: dir)"))
        XCTAssertTrue(formatReader.contains("self.tempDir = nil"))
        XCTAssertTrue(formatReader.contains("setupSucceeded = true"))

        XCTAssertTrue(initWriter.contains("var writeSucceeded = false"))
        XCTAssertTrue(initWriter.contains("if !writeSucceeded"))
        XCTAssertTrue(initWriter.contains("try? FileManager.default.removeItem(at: destinationURL)"))
        XCTAssertTrue(initWriter.contains("writeSucceeded = true"))
    }

    func testMediaReaderRejectsCompressedMediaBeforeOffsetBasedInitWriter() throws {
        let formatReader = try readSource("SVPMediaReader/SVPFormatReader.swift")

        guard let compressedCheck = formatReader.range(of: "guard !mediaInfo.isCompressed else") else {
            XCTFail("Missing compressed media guard")
            return
        }
        guard let offsetLookup = formatReader.range(of: "let mediaDataOffset = try reader.mediaDataOffset(mediaInfo)") else {
            XCTFail("Missing mediaDataOffset lookup")
            return
        }
        guard let initWriterCall = formatReader.range(of: "SVPMP4InitializationSegmentWriter.write") else {
            XCTFail("Missing init writer call")
            return
        }

        XCTAssertLessThan(compressedCheck.lowerBound, offsetLookup.lowerBound)
        XCTAssertLessThan(compressedCheck.lowerBound, initWriterCall.lowerBound)
        XCTAssertTrue(formatReader.contains("SVPError.unsupportedCodec"))
        XCTAssertTrue(formatReader.contains("stored media entries for offset-based playback"))
    }

    func testQuickLookPreviewUsesViewBasedPlayerPath() throws {
        let previewSource = try readSource("SVPPreview/PreviewProvider.swift")
        let resourceLoaderSource = try readSource("SVPPreview/SVPMediaResourceLoader.swift")
        let infoPlist = try readSource("SVPPreview/Info.plist")

        XCTAssertTrue(previewSource.contains("NSViewController"))
        XCTAssertTrue(previewSource.contains("QLPreviewingController"))
        XCTAssertTrue(previewSource.contains("preparePreviewOfFile(at url:"))
        XCTAssertTrue(previewSource.contains("AVPlayerView"))
        XCTAssertTrue(previewSource.contains("SVPMediaResourceLoader"))
        XCTAssertTrue(previewSource.contains("asset.resourceLoader.setDelegate"))
        XCTAssertTrue(previewSource.contains("AVURLAsset(url: mediaURL)"))
        XCTAssertTrue(previewSource.contains("viewDidAppear"))
        XCTAssertTrue(previewSource.contains("autoPlayIfNeeded"))
        XCTAssertTrue(previewSource.contains("window.level.rawValue > 0"))
        XCTAssertTrue(previewSource.contains("Timer.scheduledTimer"))
        XCTAssertTrue(previewSource.contains("viewWillDisappear"))
        XCTAssertTrue(previewSource.contains("viewDidDisappear"))
        XCTAssertTrue(previewSource.contains("pausePreviewPlayback"))
        XCTAssertTrue(previewSource.contains("tearDownPreviewPlayback"))
        XCTAssertTrue(resourceLoaderSource.contains("AVAssetResourceLoaderDelegate"))
        XCTAssertTrue(resourceLoaderSource.contains("readMediaDataRange"))
        XCTAssertTrue(resourceLoaderSource.contains("respond(with: data)"))
        XCTAssertFalse(previewSource.contains("QLPreviewProvider"))
        XCTAssertFalse(previewSource.contains("providePreview(for:"))
        XCTAssertFalse(previewSource.contains("materializePrimaryMedia"))
        XCTAssertFalse(previewSource.contains("extractEntry"))
        XCTAssertFalse(previewSource.contains("openAndMaterialize"))
        XCTAssertFalse(resourceLoaderSource.contains("materializePrimaryMedia"))
        XCTAssertFalse(resourceLoaderSource.contains("extractEntry"))
        XCTAssertFalse(resourceLoaderSource.contains("openAndMaterialize"))
        XCTAssertFalse(infoPlist.contains("QLIsDataBasedPreview"))
    }

    func testRelationshipStoreReadsRowsByOffset() throws {
        let fixtureURL = repositoryRoot.appendingPathComponent("SVPSystemSupportTests/Resources/SVP-TEST.svp")
        let store = try SVPInspectorJSONLStore(
            packageURL: fixtureURL,
            entryName: "relationships/relationships.jsonl"
        )

        XCTAssertEqual(store.rowCount, 47)
        XCTAssertEqual(store.uncompressedSize, 12_875)

        let firstRow = try XCTUnwrap(store.row(at: 0))
        XCTAssertEqual(firstRow["source_id"] as? String, "embed_text_obs_000001")
        XCTAssertEqual(firstRow["type"] as? String, "embedding_source_is")
        XCTAssertEqual(firstRow["target_id"] as? String, "text_region_000001")
        XCTAssertEqual(store.microsecondsText(at: 0, key: "start_us"), "0.000")
        XCTAssertEqual(store.microsecondsText(at: 0, key: "end_us"), "0.000")
        XCTAssertEqual(store.text(at: 0, key: "confidence"), "1")

        let lastRow = try XCTUnwrap(store.row(at: store.rowCount - 1))
        XCTAssertEqual(lastRow["source_id"] as? String, "word_000005")
        XCTAssertEqual(lastRow["type"] as? String, "word_spoken_by")
        XCTAssertEqual(lastRow["target_id"] as? String, "speaker_0002")
        XCTAssertEqual(store.microsecondsText(at: store.rowCount - 1, key: "start_us"), "3.725")
        XCTAssertEqual(store.microsecondsText(at: store.rowCount - 1, key: "end_us"), "4.450")
        XCTAssertEqual(store.text(at: store.rowCount - 1, key: "confidence"), "0")

        XCTAssertNil(store.row(at: store.rowCount))
    }

    func testRelationshipStoreHandlesMissingRelationshipsEntry() throws {
        let fixtureURL = try makeMinimalSVPPackage()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let beforeTempDirs = inspectorJSONLTempDirectories()

        do {
            let store = try SVPInspectorJSONLStore(
                packageURL: fixtureURL,
                entryName: "relationships/relationships.jsonl"
            )
            XCTAssertEqual(store.rowCount, 0)
            XCTAssertNil(store.uncompressedSize)
            XCTAssertNil(store.row(at: 0))
        }

        XCTAssertEqual(inspectorJSONLTempDirectories(), beforeTempDirs)
    }

    func testColorObservationDefaultOrderFollowsTimelineHierarchy() throws {
        let fixtureURL = repositoryRoot.appendingPathComponent("SVPSystemSupportTests/Resources/SVP-TEST.svp")
        let store = try SVPInspectorJSONLStore(
            packageURL: fixtureURL,
            entryName: "colors/color_observations.jsonl"
        )

        let rowIndexes = colorObservationAppearanceRowIndexes(for: store)

        XCTAssertEqual(rowIndexes.count, store.rowCount)

        let first = try XCTUnwrap(store.row(at: rowIndexes[0]))
        XCTAssertEqual(first["target_type"] as? String, "scene")
        XCTAssertEqual(first["target_id"] as? String, "scene_000001")
        XCTAssertEqual(first["start_us"] as? Int, 193_333)

        let second = try XCTUnwrap(store.row(at: rowIndexes[1]))
        XCTAssertEqual(second["target_type"] as? String, "shot")
        XCTAssertEqual(second["target_id"] as? String, "shot_000001")
        XCTAssertEqual(second["start_us"] as? Int, 193_333)

        let third = try XCTUnwrap(store.row(at: rowIndexes[2]))
        XCTAssertEqual(third["target_type"] as? String, "frame")
        XCTAssertEqual(third["target_id"] as? String, "frame_000001")
        XCTAssertEqual(third["start_us"] as? Int, 193_333)
    }

    func testColorObservationDefaultOrderReadsEachRowOnce() {
        let rows: [[String: Any]] = [
            ["target_type": "frame", "target_id": "frame_2", "start_us": 2, "end_us": 3],
            ["target_type": "scene", "target_id": "scene_1", "start_us": 1, "end_us": 4],
            ["target_type": "shot", "target_id": "shot_1", "start_us": 1, "end_us": 2]
        ]
        var readCounts = Array(repeating: 0, count: rows.count)

        let indexes = colorObservationAppearanceRowIndexes(rowCount: rows.count) { index in
            readCounts[index] += 1
            return rows[index]
        }

        XCTAssertEqual(indexes, [1, 2, 0])
        XCTAssertEqual(readCounts, [1, 1, 1])
    }

    func testInspectorDefaultRowOrderingRunsOffMainThread() throws {
        let fixtureURL = repositoryRoot.appendingPathComponent("SVPSystemSupportTests/Resources/SVP-TEST.svp")
        let store = try SVPInspectorJSONLStore(
            packageURL: fixtureURL,
            entryName: "colors/color_observations.jsonl"
        )
        let completed = expectation(description: "default ordering completed")
        let coordinator = InspectorJSONLTableView.Coordinator(
            store: store,
            columns: [],
            defaultRowOrder: { store in
                XCTAssertFalse(Thread.isMainThread)
                defer { completed.fulfill() }
                return Array(0..<store.rowCount)
            }
        )

        coordinator.applySortDescriptors([], tableView: nil)

        wait(for: [completed], timeout: 2)
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeMinimalSVPPackage() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-minimal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "application/vnd.svp+zip\n".write(
            to: root.appendingPathComponent("mimetype"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "svp_version": "1.0",
          "package_id": "missing_relationships_fixture",
          "created_utc": "2026-07-03T00:00:00Z",
          "primary_media_id": "media_000001",
          "timebase": {
            "unit": "microseconds",
            "origin": "media"
          }
        }
        """.write(
            to: root.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-minimal-\(UUID().uuidString).svp")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-X", packageURL.path, "mimetype", "manifest.json"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        return packageURL
    }

    private func inspectorJSONLTempDirectories() -> Set<String> {
        let tempURL = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: tempURL.path
        )) ?? []
        return Set(names.filter { $0.hasPrefix("svp-inspector-jsonl-") })
    }

    func testEmbeddedFinderServicesAdvertiseEverySystemMediaUTI() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)
        let services = try XCTUnwrap(plist["NSServices"] as? [[String: Any]])
        let required = Set(SVPPasteboardReader.systemMediaUTIs)
        for title in ["Show Embedded SVPI Transcript", "Extract SVPI from Media", "Embedded SVPI Inspector"] {
            let service = try XCTUnwrap(services.first { (($0["NSMenuItem"] as? [String: String])?["default"]) == title })
            XCTAssertEqual(Set(try XCTUnwrap(service["NSSendFileTypes"] as? [String])), required)
        }
        XCTAssertEqual(required, Set(["public.mpeg-4", "com.apple.quicktime-movie", "com.apple.m4v-video", "public.mpeg-4-audio", "com.apple.m4a-audio"]))
    }

    func testEmbeddedFinderServiceResolutionRunsOffMainThreadAndCompletesOnMainThread() {
        let completed = expectation(description: "resolution completed")
        EmbeddedSVPIFinderServiceRouter.resolve(
            mediaURL: URL(fileURLWithPath: "/tmp/media.mp4"),
            resolver: { _ in
                XCTAssertFalse(Thread.isMainThread)
                return .noEmbeddedSvpi
            },
            completion: { status in
                XCTAssertTrue(Thread.isMainThread)
                guard case .noEmbeddedSvpi = status else {
                    return XCTFail("Expected no-embedding status")
                }
                completed.fulfill()
            }
        )
        wait(for: [completed], timeout: 2)
    }

    func testEmbeddedSVPIExtractorWritesTheBoundedPackagePayload() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-svpi-source-\(UUID().uuidString).svpi")
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-svpi-output-\(UUID().uuidString).svpi")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let expected = Data((0..<257).map { UInt8($0 % 251) })
        try expected.write(to: sourceURL)
        let package = try SVPPackageDescriptor.standalone(url: sourceURL)

        try EmbeddedSVPIExtractor.write(package: package, to: destinationURL, bufferSize: 17)

        XCTAssertEqual(try Data(contentsOf: destinationURL), expected)
    }

    func testRealEmbeddedDescriptorFeedsEveryLazyInspectorSection() throws {
        let url = URL(fileURLWithPath: "/Users/domesposito/Desktop/test-30-semantic.mp4")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Real semantic sample unavailable") }
        guard case .embedded(let package) = SemanticMediaResolver.resolve(url: url) else { return XCTFail("Real sample did not resolve") }
        let viewModel = SVPInspectorViewModel(fileURL: url, formatLabel: "Embedded SVPI", package: package)
        XCTAssertEqual(viewModel.windowTitle, "test-30-semantic — Embedded SVPI Inspector")
        XCTAssertEqual(try SVPInspectorDataLoader.loadOverview(from: url, package: package).manifest?.packageID, "svpi_test-30_pkg")
        XCTAssertEqual(try SVPInspectorDataLoader.loadTranscript(from: url, package: package).words.rowCount, 58)
        XCTAssertEqual(try SVPInspectorDataLoader.loadText(from: url, package: package).observations.rowCount, 23)
        _ = try SVPInspectorDataLoader.loadEvidenceCrops(from: url, package: package)
        XCTAssertEqual(try SVPInspectorDataLoader.loadColors(from: url, package: package).observations.rowCount, 37)
        _ = try SVPInspectorDataLoader.loadTimeline(from: url, package: package)
        _ = try SVPInspectorDataLoader.loadEntities(from: url, package: package)
        XCTAssertEqual(try SVPInspectorDataLoader.loadRelationships(from: url, package: package).store.rowCount, 296)
        _ = try SVPInspectorDataLoader.loadProvenance(from: url, package: package)
        _ = try SVPInspectorDataLoader.loadIndex(from: url, package: package)
        XCTAssertEqual(try SVPTranscriptLoader().loadTranscript(from: package).split(separator: " ").count, 58)
        XCTAssertEqual(package.payloadOffset, viewModel.package?.payloadOffset)
    }

    func testRealEmbeddedPackageOpensExistingTranscriptAndInspectorWindows() throws {
        let url = URL(fileURLWithPath: "/Users/domesposito/Desktop/test-30-semantic.mp4")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Real semantic sample unavailable") }
        guard case .embedded(let package) = SemanticMediaResolver.resolve(url: url) else { return XCTFail("Real sample did not resolve") }

        let transcriptPresenter = SVPTranscriptWindowPresenter()
        let transcriptWindow = transcriptPresenter.presentLoading(title: "test-30-semantic Transcript")
        transcriptPresenter.completeLoading(window: transcriptWindow, text: try SVPTranscriptLoader().loadTranscript(from: package))
        XCTAssertTrue(transcriptPresenter.contains(transcriptWindow))

        let inspector = SVPInspectorWindowController(viewModel: SVPInspectorViewModel(fileURL: url, formatLabel: "Embedded SVPI", package: package))
        inspector.present()
        XCTAssertEqual(inspector.window?.title, "test-30-semantic — Embedded SVPI Inspector")
        XCTAssertTrue(inspector.window?.isVisible == true)

        transcriptPresenter.close(window: transcriptWindow)
        inspector.close()
    }
}
