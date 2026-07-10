import XCTest
@testable import SVPReader

final class SVPReaderTests: XCTestCase {

    var sampleSVPURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SVPSystemSupportTests/Resources/SVP-TEST.svp")
    }

    func testOpenAndValidateSVP() throws {
        let reader = try SVPReader(url: sampleSVPURL)
        try reader.validateSVP()
    }

    func testReadManifest() throws {
        let reader = try SVPReader(url: sampleSVPURL)
        let manifest = try reader.readManifest()
        XCTAssertEqual(manifest.svpVersion, "1.0-rc.2")
        XCTAssertEqual(manifest.packageID, "svp_SVP-TEST_pkg")
        XCTAssertEqual(manifest.primaryMediaID, "media_000001")
    }

    func testLocatePrimaryMedia() throws {
        let reader = try SVPReader(url: sampleSVPURL)
        let media = try reader.locatePrimaryMediaAsset()
        XCTAssertEqual(media.mediaPath, "media/original/source_000.MOV")
        XCTAssertEqual(media.fileExtension.lowercased(), "mov")
        XCTAssertTrue(media.likelyPlayableByAVFoundation)
        XCTAssertGreaterThan(media.uncompressedSize, 0)
    }

    func testMaterializePrimaryMedia() throws {
        let reader = try SVPReader(url: sampleSVPURL)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-test-\(UUID().uuidString)", isDirectory: true)
        defer { SVPReader.cleanupMaterializedMedia(at: tempDir) }

        let mediaURL = try reader.materializePrimaryMedia(to: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: mediaURL.path)
        let size = attrs[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testOpenAndMaterialize() throws {
        let reader = try SVPReader(url: sampleSVPURL)
        let result = try reader.openAndMaterialize()
        defer { SVPReader.cleanupMaterializedMedia(at: result.tempDir!) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.mediaURL.path))
        XCTAssertEqual(result.mediaInfo.mediaFileName, "source_000.MOV")
    }

    func testInvalidFile() {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-svp.txt")
        try? "hello".data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        XCTAssertThrowsError(try SVPReader(url: tempFile)) { error in
            guard case ZipReaderError.notZipArchive = error else {
                XCTFail("Expected notZipArchive error, got: \(error)")
                return
            }
        }
    }

    func testValidateRejectsUnexpectedMimetype() throws {
        let fixture = try makeSVPFixture(mimetype: "text/plain")
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        XCTAssertThrowsError(try SVPReader(url: fixture.svpURL).validateSVP()) { error in
            guard case SVPError.notSVPFile(let message) = error else {
                XCTFail("Expected notSVPFile error, got: \(error)")
                return
            }
            XCTAssertTrue(message.contains("Unexpected mimetype"))
        }
    }

    func testValidateRejectsMissingManifest() throws {
        let fixture = try makeSVPFixture(includeManifest: false)
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        XCTAssertThrowsError(try SVPReader(url: fixture.svpURL).validateSVP()) { error in
            guard case SVPError.manifestReadFailed(let message) = error else {
                XCTFail("Expected manifestReadFailed error, got: \(error)")
                return
            }
            XCTAssertTrue(message.contains("No manifest.json"))
        }
    }

    func testReadManifestRejectsMalformedJSON() throws {
        let fixture = try makeSVPFixture(manifestJSON: "{not json")
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        XCTAssertThrowsError(try SVPReader(url: fixture.svpURL).readManifest()) { error in
            guard case SVPError.manifestParseFailed(let message) = error else {
                XCTFail("Expected manifestParseFailed error, got: \(error)")
                return
            }
            XCTAssertTrue(message.contains("JSON parse failed"))
        }
    }

    func testLocatePrimaryMediaRejectsPackageWithoutOriginalMedia() throws {
        let fixture = try makeSVPFixture(mediaFiles: [:])
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        XCTAssertThrowsError(try SVPReader(url: fixture.svpURL).locatePrimaryMediaAsset()) { error in
            guard case SVPError.noMediaFound(let message) = error else {
                XCTFail("Expected noMediaFound error, got: \(error)")
                return
            }
            XCTAssertTrue(message.contains("media/original"))
        }
    }

    func testLocatePrimaryMediaSelectsFirstSortedMediaEntryWhenMultipleExist() throws {
        let fixture = try makeSVPFixture(mediaFiles: [
            "media/original/z-last.mov": Data("last".utf8),
            "media/original/a-first.mp4": Data("first".utf8)
        ])
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let media = try SVPReader(url: fixture.svpURL).locatePrimaryMediaAsset()

        XCTAssertEqual(media.mediaPath, "media/original/a-first.mp4")
        XCTAssertEqual(media.mediaFileName, "a-first.mp4")
        XCTAssertEqual(media.fileExtension, "mp4")
    }

    func testReadTranscriptTextJoinsJSONLWords() throws {
        let fixture = try makeSVPFixture(transcriptLines: [
            #"{"text":"hello","start":0}"#,
            #"{"text":"semantic","start":1}"#,
            #"{"text":"video","start":2}"#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let transcript = try SVPReader(url: fixture.svpURL).readTranscriptText()

        XCTAssertEqual(transcript, "hello semantic video")
    }

    func testReadTranscriptTextKeepsSentencePunctuationInFlow() throws {
        let fixture = try makeSVPFixture(transcriptLines: [
            #"{"text":"Hello.","start_us":0,"end_us":500000}"#,
            #"{"text":"This","start_us":600000,"end_us":700000}"#,
            #"{"text":"continues","start_us":700000,"end_us":800000}"#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let transcript = try SVPReader(url: fixture.svpURL).readTranscriptText()

        XCTAssertEqual(transcript, "Hello. This continues")
    }

    func testReadTranscriptTextBreaksOnlyOnSentenceBoundaryWithSilence() throws {
        let fixture = try makeSVPFixture(transcriptLines: [
            #"{"text":"Speaker","start_us":0,"end_us":250000,"speaker_id":"speaker_0001","chunk_ordinal":0}"#,
            #"{"text":"one","start_us":250000,"end_us":500000,"speaker_id":"speaker_0001","chunk_ordinal":0}"#,
            #"{"text":"Speaker","start_us":500000,"end_us":750000,"speaker_id":"speaker_0002","chunk_ordinal":0}"#,
            #"{"text":"two.","start_us":750000,"end_us":1000000,"speaker_id":"speaker_0002","chunk_ordinal":0}"#,
            #"{"text":"Later","start_us":3000000,"end_us":3250000,"speaker_id":"speaker_0002","chunk_ordinal":0}"#,
            #"{"text":"chunk","start_us":3250000,"end_us":3500000,"speaker_id":"speaker_0002","chunk_ordinal":1}"#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let transcript = try SVPReader(url: fixture.svpURL).readTranscriptText()

        XCTAssertEqual(transcript, "Speaker one Speaker two.\n\nLater chunk")
    }

    func testTranscriptFormatterKeepsSubthresholdSentencePauseInOneParagraph() {
        let words = [
            TranscriptWordRecord(text: "Done.", startUS: 0, endUS: 500_000),
            TranscriptWordRecord(text: "Next", startUS: 1_099_999, endUS: 1_200_000)
        ]

        XCTAssertEqual(TranscriptFormatter.format(words), "Done. Next")
    }

    func testTranscriptFormatterKeepsLongMidSentencePauseInOneParagraph() {
        let words = [
            TranscriptWordRecord(text: "Still", startUS: 0, endUS: 500_000),
            TranscriptWordRecord(text: "together", startUS: 3_000_000, endUS: 3_100_000)
        ]

        XCTAssertEqual(TranscriptFormatter.format(words), "Still together")
    }

    func testTranscriptFormatterBreaksAfterQuotedSentenceAndSixHundredMillisecondPause() {
        let words = [
            TranscriptWordRecord(text: "Done.”", startUS: 0, endUS: 500_000),
            TranscriptWordRecord(text: "Next", startUS: 1_100_000, endUS: 1_200_000)
        ]

        XCTAssertEqual(TranscriptFormatter.format(words), "Done.”\n\nNext")
    }

    func testTranscriptFormatterHandlesTimestampBoundariesWithoutOverflow() {
        let words = [
            TranscriptWordRecord(text: "Boundary", startUS: Int64.max - 1, endUS: Int64.max),
            TranscriptWordRecord(text: "safe", startUS: Int64.max, endUS: Int64.max)
        ]

        XCTAssertEqual(TranscriptFormatter.format(words), "Boundary safe")
    }

    func testReadTranscriptTextRejectsMissingWordsEntry() throws {
        let fixture = try makeSVPFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        XCTAssertThrowsError(try SVPReader(url: fixture.svpURL).readTranscriptText()) { error in
            guard case SVPError.ioError(let message) = error else {
                XCTFail("Expected ioError, got: \(error)")
                return
            }
            XCTAssertTrue(message.contains("No transcript words"))
        }
    }

    func testMediaDataOffsetPointsAtStoredMediaPayload() throws {
        let fixture = try makeStoredSVPFixture(mediaBytes: Data("stored-media-payload".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let reader = try SVPReader(url: fixture.svpURL)
        let media = try reader.locatePrimaryMediaAsset()
        let offset = try reader.mediaDataOffset(media)
        let handle = try FileHandle(forReadingFrom: fixture.svpURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        let bytesAtOffset = try XCTUnwrap(try handle.read(upToCount: fixture.mediaBytes.count))
        XCTAssertEqual(bytesAtOffset, fixture.mediaBytes)
    }

    func testExtractMediaDataWritesStoredEntryWithoutMaterializingInCaller() throws {
        let fixture = try makeStoredSVPFixture(mediaBytes: Data((0..<4096).map { UInt8($0 % 251) }))
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let reader = try SVPReader(url: fixture.svpURL)
        let media = try reader.locatePrimaryMediaAsset()
        let outputURL = fixture.tempDir.appendingPathComponent("extracted.mov")

        try reader.extractMediaData(media, to: outputURL)

        XCTAssertEqual(try Data(contentsOf: outputURL), fixture.mediaBytes)
    }

    func testMaterializePrimaryMediaWritesExactMediaBytes() throws {
        let fixture = try makeStoredSVPFixture(mediaBytes: Data("exact-materialized-media".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }
        let outputDir = fixture.tempDir.appendingPathComponent("materialized", isDirectory: true)

        let mediaURL = try SVPReader(url: fixture.svpURL).materializePrimaryMedia(to: outputDir)

        XCTAssertEqual(try Data(contentsOf: mediaURL), fixture.mediaBytes)
    }

    func testExtractMediaDataInflatesDeflatedEntry() throws {
        let fixture = try makeDeflatedSVPFixture(mediaBytes: Data(String(repeating: "compressed-media-", count: 256).utf8))
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let reader = try SVPReader(url: fixture.svpURL)
        let media = try reader.locatePrimaryMediaAsset()
        let outputURL = fixture.tempDir.appendingPathComponent("inflated.mov")

        try reader.extractMediaData(media, to: outputURL)

        XCTAssertEqual(try Data(contentsOf: outputURL), fixture.mediaBytes)
    }

    private struct SVPFixture {
        let tempDir: URL
        let svpURL: URL
        let mediaBytes: Data
    }

    private func makeStoredSVPFixture(mediaBytes: Data) throws -> SVPFixture {
        try makeSVPFixture(mediaBytes: mediaBytes, zipCompressionFlag: "-0")
    }

    private func makeDeflatedSVPFixture(mediaBytes: Data) throws -> SVPFixture {
        try makeSVPFixture(mediaBytes: mediaBytes, zipCompressionFlag: "-9")
    }

    private func makeSVPFixture(
        mediaBytes: Data = Data("media".utf8),
        zipCompressionFlag: String = "-0",
        mimetype: String = "application/vnd.svp+zip",
        includeManifest: Bool = true,
        manifestJSON: String? = nil,
        mediaFiles: [String: Data]? = nil,
        transcriptLines: [String] = []
    ) throws -> SVPFixture {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-reader-test-\(UUID().uuidString)", isDirectory: true)
        let packageDir = tempDir.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        try Data(mimetype.utf8)
            .write(to: packageDir.appendingPathComponent("mimetype"))

        if includeManifest {
            let manifest = manifestJSON ?? """
            {
              "svp_version": "1.0-test",
              "package_id": "test_pkg",
              "primary_media_id": "media_000001"
            }
            """
            try Data(manifest.utf8).write(to: packageDir.appendingPathComponent("manifest.json"))
        }

        let files = mediaFiles ?? ["media/original/source_000.mov": mediaBytes]
        for (relativePath, data) in files {
            let url = packageDir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        if !transcriptLines.isEmpty {
            let transcriptDir = packageDir.appendingPathComponent("transcript", isDirectory: true)
            try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
            try Data((transcriptLines.joined(separator: "\n") + "\n").utf8)
                .write(to: transcriptDir.appendingPathComponent("words.jsonl"))
        }

        let svpURL = tempDir.appendingPathComponent("fixture.svp")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        var zipPaths = ["mimetype", "media"]
        if includeManifest {
            zipPaths.insert("manifest.json", at: 1)
        }
        if !transcriptLines.isEmpty {
            zipPaths.append("transcript")
        }
        process.arguments = [zipCompressionFlag, "-q", "-r", svpURL.path] + zipPaths
        process.currentDirectoryURL = packageDir
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        return SVPFixture(tempDir: tempDir, svpURL: svpURL, mediaBytes: mediaBytes)
    }
}
