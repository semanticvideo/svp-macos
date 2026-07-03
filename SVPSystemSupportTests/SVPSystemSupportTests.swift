//
//  SVPSystemSupportTests.swift
//  SVPSystemSupportTests
//
//  Created by Dom Esposito on 6/21/26.
//

import XCTest
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
        let store = try SVPRelationshipJSONLStore(packageURL: fixtureURL)

        XCTAssertEqual(store.rowCount, 47)
        XCTAssertEqual(store.uncompressedSize, 12_875)

        let firstRow = try XCTUnwrap(store.row(at: 0))
        XCTAssertEqual(firstRow.sourceID, "embed_text_obs_000001")
        XCTAssertEqual(firstRow.type, "embedding_source_is")
        XCTAssertEqual(firstRow.targetID, "text_region_000001")
        XCTAssertEqual(firstRow.startText, "0.000")
        XCTAssertEqual(firstRow.endText, "0.000")
        XCTAssertEqual(firstRow.confidence, "1")

        let lastRow = try XCTUnwrap(store.row(at: store.rowCount - 1))
        XCTAssertEqual(lastRow.sourceID, "word_000005")
        XCTAssertEqual(lastRow.type, "word_spoken_by")
        XCTAssertEqual(lastRow.targetID, "speaker_0002")
        XCTAssertEqual(lastRow.startText, "3.725")
        XCTAssertEqual(lastRow.endText, "4.450")
        XCTAssertEqual(lastRow.confidence, "0")

        XCTAssertNil(store.row(at: store.rowCount))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
