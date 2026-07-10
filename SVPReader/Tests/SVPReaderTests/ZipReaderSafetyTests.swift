import Foundation
import XCTest
@testable import SVPReader

final class ZipReaderSafetyTests: XCTestCase {
    func testDuplicateCentralDirectoryNamesAreRejected() throws {
        let archive = makeCentralDirectoryOnlyArchive(names: ["mimetype", "mimetype"])

        XCTAssertThrowsError(try ZipReader(source: TestByteSource(archive))) { error in
            guard case ZipReaderError.readFailed(let message) = error else {
                return XCTFail("Expected a ZIP read failure, got \(error)")
            }
            XCTAssertTrue(message.contains("duplicate entry names"))
        }
    }

    func testCentralDirectoryIsReadInBoundedRecords() throws {
        let names = (0..<2_000).map { String(format: "entry-%04d", $0) }
        let source = RecordingByteSource(makeCentralDirectoryOnlyArchive(names: names))

        let reader = try ZipReader(source: source)

        XCTAssertEqual(reader.entryNames.count, names.count)
        XCTAssertLessThanOrEqual(source.maximumRequestedLength, 65_557)
    }

    func testZIP64EndRecordsAndEntryExtraFieldsAreResolved() throws {
        let payload = Data("zip64-payload".utf8)
        let source = TestByteSource(makeZIP64Archive(name: "payload.bin", payload: payload))

        let reader = try ZipReader(source: source)

        XCTAssertEqual(try reader.readEntry("payload.bin"), payload)
    }
}

private func makeCentralDirectoryOnlyArchive(names: [String]) -> Data {
    var centralDirectory = Data()
    for name in names {
        let nameData = Data(name.utf8)
        centralDirectory += le32(0x02014b50)
        centralDirectory += le16(20) + le16(20) + le16(0) + le16(0)
        centralDirectory += le16(0) + le16(0) + le32(0) + le32(0) + le32(0)
        centralDirectory += le16(UInt16(nameData.count)) + le16(0) + le16(0)
        centralDirectory += le16(0) + le16(0) + le32(0) + le32(0)
        centralDirectory += nameData
    }
    var archive = centralDirectory
    archive += le32(0x06054b50) + le16(0) + le16(0)
    archive += le16(UInt16(names.count)) + le16(UInt16(names.count))
    archive += le32(UInt32(centralDirectory.count)) + le32(0) + le16(0)
    return archive
}

private func makeZIP64Archive(name: String, payload: Data) -> Data {
    let nameData = Data(name.utf8)
    let localZIP64Data = le64(UInt64(payload.count)) + le64(UInt64(payload.count))
    let localExtra = le16(0x0001) + le16(UInt16(localZIP64Data.count)) + localZIP64Data

    var archive = Data()
    archive += le32(0x04034b50) + le16(45) + le16(0) + le16(0)
    archive += le16(0) + le16(0) + le32(0) + le32(UInt32.max) + le32(UInt32.max)
    archive += le16(UInt16(nameData.count)) + le16(UInt16(localExtra.count))
    archive += nameData + localExtra + payload

    let centralDirectoryOffset = UInt64(archive.count)
    let centralZIP64Data = le64(UInt64(payload.count)) + le64(UInt64(payload.count)) + le64(0)
    let centralExtra = le16(0x0001) + le16(UInt16(centralZIP64Data.count)) + centralZIP64Data
    var centralDirectory = Data()
    centralDirectory += le32(0x02014b50) + le16(45) + le16(45) + le16(0) + le16(0)
    centralDirectory += le16(0) + le16(0) + le32(0) + le32(UInt32.max) + le32(UInt32.max)
    centralDirectory += le16(UInt16(nameData.count)) + le16(UInt16(centralExtra.count)) + le16(0)
    centralDirectory += le16(0) + le16(0) + le32(0) + le32(UInt32.max)
    centralDirectory += nameData + centralExtra
    archive += centralDirectory

    let zip64RecordOffset = UInt64(archive.count)
    archive += le32(0x06064b50) + le64(44) + le16(45) + le16(45)
    archive += le32(0) + le32(0) + le64(1) + le64(1)
    archive += le64(UInt64(centralDirectory.count)) + le64(centralDirectoryOffset)
    archive += le32(0x07064b50) + le32(0) + le64(zip64RecordOffset) + le32(1)
    archive += le32(0x06054b50) + le16(0) + le16(0)
    archive += le16(UInt16.max) + le16(UInt16.max)
    archive += le32(UInt32.max) + le32(UInt32.max) + le16(0)
    return archive
}

private struct TestByteSource: SVPPackageByteSource {
    let data: Data
    init(_ data: Data) { self.data = data }
    var length: UInt64 { UInt64(data.count) }

    func read(offset: UInt64, length: Int) throws -> Data {
        guard length >= 0 else { throw SVPPackageByteSourceError.invalidLength }
        let (end, overflow) = offset.addingReportingOverflow(UInt64(length))
        guard !overflow, end <= UInt64(data.count) else { throw SVPPackageByteSourceError.outOfRange }
        return Data(data[Int(offset)..<Int(end)])
    }
}

private final class RecordingByteSource: SVPPackageByteSource, @unchecked Sendable {
    let data: Data
    private(set) var maximumRequestedLength = 0

    init(_ data: Data) { self.data = data }
    var length: UInt64 { UInt64(data.count) }

    func read(offset: UInt64, length: Int) throws -> Data {
        maximumRequestedLength = max(maximumRequestedLength, length)
        return try TestByteSource(data).read(offset: offset, length: length)
    }
}

private func le16(_ value: UInt16) -> Data {
    Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
}

private func le32(_ value: UInt32) -> Data {
    Data((0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32($0 * 8)) })
}

private func le64(_ value: UInt64) -> Data {
    Data((0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) })
}
