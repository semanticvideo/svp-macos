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

    func testEmbeddedFinderServicesUseStableMessagesAndSupportedUTIs() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)
        let services = try XCTUnwrap(plist["NSServices"] as? [[String: Any]])
        let required = Set(SVPPasteboardReader.systemMediaUTIs)
        let app = SVPSystemSupportApp()
        let serviceSelectors = [
            ("showEmbeddedSVPITranscriptService", #selector(SVPSystemSupportApp.showEmbeddedSVPITranscriptService(_:userData:error:))),
            ("extractEmbeddedSVPIService", #selector(SVPSystemSupportApp.extractEmbeddedSVPIService(_:userData:error:))),
            ("inspectEmbeddedSVPIService", #selector(SVPSystemSupportApp.inspectEmbeddedSVPIService(_:userData:error:)))
        ]
        for (message, selector) in serviceSelectors {
            let service = try XCTUnwrap(services.first { ($0["NSMessage"] as? String) == message })
            XCTAssertEqual(Set(try XCTUnwrap(service["NSSendFileTypes"] as? [String])), required)
            XCTAssertTrue(app.responds(to: selector))
        }
        XCTAssertEqual(required, Set(["public.mpeg-4", "com.apple.quicktime-movie", "com.apple.m4v-video", "public.mpeg-4-audio", "com.apple.m4a-audio"]))
    }

    func testEmbeddedFinderServiceResolutionRunsOffMainThreadAndCompletesOnMainThread() {
        let completed = expectation(description: "resolution completed")
        let mediaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-service-\(UUID().uuidString).mp4")
        EmbeddedSVPIFinderServiceRouter.resolve(
            mediaURL: mediaURL,
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
            .appendingPathComponent("embedded-svpi-container-\(UUID().uuidString).mp4")
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-svpi-output-\(UUID().uuidString).svpi")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let prefix = Data(repeating: 0xAA, count: 31)
        let expected = Data((0..<257).map { UInt8($0 % 251) })
        let suffix = Data(repeating: 0xBB, count: 29)
        try (prefix + expected + suffix).write(to: sourceURL)
        try Data("previous destination".utf8).write(to: destinationURL)
        let fileSource = try FilePackageByteSource(url: sourceURL)
        let boundedSource = try BoundedPackageByteSource(
            source: fileSource,
            baseOffset: UInt64(prefix.count),
            length: UInt64(expected.count)
        )

        try EmbeddedSVPIExtractor.write(
            source: boundedSource,
            sourceMediaURL: sourceURL,
            to: destinationURL,
            bufferSize: 17
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), expected)
    }

    func testEmbeddedSVPIExtractorPreservesExistingDestinationWhenReadFails() throws {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-svpi-existing-\(UUID().uuidString).svpi")
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let existingData = Data("existing".utf8)
        try existingData.write(to: destinationURL)

        XCTAssertThrowsError(try EmbeddedSVPIExtractor.write(
            source: FailingPackageByteSource(),
            sourceMediaURL: destinationURL.appendingPathExtension("source"),
            to: destinationURL,
            bufferSize: 1
        ))
        XCTAssertEqual(try Data(contentsOf: destinationURL), existingData)
    }

    func testEmbeddedSVPIExtractorRejectsSourceMediaAsDestination() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-svpi-source-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let sourceData = Data("source media".utf8)
        try sourceData.write(to: sourceURL)
        let source = try FilePackageByteSource(url: sourceURL)

        XCTAssertThrowsError(try EmbeddedSVPIExtractor.write(
            source: source,
            sourceMediaURL: sourceURL,
            to: sourceURL,
            bufferSize: 1
        ))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

}

private struct FailingPackageByteSource: SVPPackageByteSource {
    let length: UInt64 = 1

    func read(offset: UInt64, length: Int) throws -> Data {
        throw CocoaError(.fileReadUnknown)
    }
}
