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

    private func readSource(_ relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
