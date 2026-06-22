import XCTest
@testable import SVPReader

final class SVPReaderTests: XCTestCase {

    var sampleSVPURL: URL {
        URL(fileURLWithPath: "/Users/domesposito/Projects/svp/build/local-code-svp/CODE.svp")
    }

    func testOpenAndValidateSVP() throws {
        let reader = try SVPReader(url: sampleSVPURL)
        try reader.validateSVP()
    }

    func testReadManifest() throws {
        let reader = try SVPReader(url: sampleSVPURL)
        let manifest = try reader.readManifest()
        XCTAssertEqual(manifest.svpVersion, "1.0-rc.2")
        XCTAssertEqual(manifest.packageID, "svp_CODE_pkg")
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
}
