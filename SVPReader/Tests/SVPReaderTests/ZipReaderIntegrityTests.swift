import CZlib
import Foundation
import XCTest
@testable import SVPReader

final class ZipReaderIntegrityTests: XCTestCase {
    func testStoredEntryReadRejectsCRCMismatch() throws {
        let payload = Data("integrity payload".utf8)
        var archive = storedArchive(name: "payload.bin", payload: payload)
        archive[storedPayloadOffset(name: "payload.bin")] ^= 0xff

        let reader = try ZipReader(source: DataByteSource(archive))

        XCTAssertThrowsError(try reader.readEntry("payload.bin")) { error in
            guard case ZipReaderError.readFailed(let message) = error else {
                return XCTFail("Expected a ZIP read failure, got \(error)")
            }
            XCTAssertTrue(message.contains("CRC32 mismatch"))
        }
    }

    func testExtractionPreservesDestinationWhenCRCDoesNotMatch() throws {
        let payload = Data("integrity payload".utf8)
        var archive = storedArchive(name: "payload.bin", payload: payload)
        archive[storedPayloadOffset(name: "payload.bin")] ^= 0xff
        let reader = try ZipReader(source: DataByteSource(archive))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-integrity-existing-\(UUID().uuidString).bin")
        let existing = Data("existing destination".utf8)
        try existing.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }

        XCTAssertThrowsError(try reader.extractEntry("payload.bin", to: destination, bufferSize: 4))
        XCTAssertEqual(try Data(contentsOf: destination), existing)
    }

    func testStoredExtractionUsesBoundedReads() throws {
        let payload = Data(repeating: 0xa5, count: 8 * 1_024 * 1_024)
        let source = RecordingDataByteSource(storedArchive(name: "payload.bin", payload: payload))
        let reader = try ZipReader(source: source)
        source.resetMaximumRequestedLength()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-bounded-extraction-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destination) }

        try reader.extractEntry("payload.bin", to: destination, bufferSize: 16 * 1_024)

        XCTAssertLessThanOrEqual(source.maximumRequestedLength, 16 * 1_024)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }

    func testZIP64StoredEntryLargerThanFourGiBSupportsRangeReads() throws {
        let entryName = "media/original/large.mov"
        let payloadSize = UInt64(UInt32.max) + 1_024
        let source = sparseZIP64Archive(name: entryName, payloadSize: payloadSize)
        let reader = try ZipReader(source: source)

        let data = try reader.readStoredEntryRange(entryName, offset: payloadSize - 8, length: 16)

        XCTAssertEqual(reader.entryInfo(entryName)?.uncompressedSize, payloadSize)
        XCTAssertEqual(data, Data(repeating: 0, count: 8))
        XCTAssertLessThanOrEqual(source.maximumRequestedLength, 65_557)
    }

    private func storedArchive(name: String, payload: Data) -> Data {
        let nameData = Data(name.utf8)
        let checksum = crc32(payload)
        let payloadSize = UInt32(payload.count)

        var local = Data()
        local += le32(0x04034b50) + le16(20) + le16(0) + le16(0)
        local += le16(0) + le16(0) + le32(checksum) + le32(payloadSize) + le32(payloadSize)
        local += le16(UInt16(nameData.count)) + le16(0) + nameData + payload

        let centralOffset = UInt32(local.count)
        var central = Data()
        central += le32(0x02014b50) + le16(20) + le16(20) + le16(0) + le16(0)
        central += le16(0) + le16(0) + le32(checksum) + le32(payloadSize) + le32(payloadSize)
        central += le16(UInt16(nameData.count)) + le16(0) + le16(0)
        central += le16(0) + le16(0) + le32(0) + le32(0) + nameData

        var archive = local + central
        archive += le32(0x06054b50) + le16(0) + le16(0) + le16(1) + le16(1)
        archive += le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        return archive
    }

    private func sparseZIP64Archive(name: String, payloadSize: UInt64) -> SparseZIP64ByteSource {
        let nameData = Data(name.utf8)
        let localZIP64Values = le64(payloadSize) + le64(payloadSize)
        let localExtra = le16(0x0001) + le16(UInt16(localZIP64Values.count)) + localZIP64Values

        var local = Data()
        local += le32(0x04034b50) + le16(45) + le16(0) + le16(0)
        local += le16(0) + le16(0) + le32(0) + le32(UInt32.max) + le32(UInt32.max)
        local += le16(UInt16(nameData.count)) + le16(UInt16(localExtra.count))
        local += nameData + localExtra

        let centralOffset = UInt64(local.count) + payloadSize
        let centralZIP64Values = le64(payloadSize) + le64(payloadSize) + le64(0)
        let centralExtra = le16(0x0001) + le16(UInt16(centralZIP64Values.count)) + centralZIP64Values
        var central = Data()
        central += le32(0x02014b50) + le16(45) + le16(45) + le16(0) + le16(0)
        central += le16(0) + le16(0) + le32(0) + le32(UInt32.max) + le32(UInt32.max)
        central += le16(UInt16(nameData.count)) + le16(UInt16(centralExtra.count)) + le16(0)
        central += le16(0) + le16(0) + le32(0) + le32(UInt32.max)
        central += nameData + centralExtra

        let zip64RecordOffset = centralOffset + UInt64(central.count)
        var tail = central
        tail += le32(0x06064b50) + le64(44) + le16(45) + le16(45)
        tail += le32(0) + le32(0) + le64(1) + le64(1)
        tail += le64(UInt64(central.count)) + le64(centralOffset)
        tail += le32(0x07064b50) + le32(0) + le64(zip64RecordOffset) + le32(1)
        tail += le32(0x06054b50) + le16(0) + le16(0)
        tail += le16(UInt16.max) + le16(UInt16.max)
        tail += le32(UInt32.max) + le32(UInt32.max) + le16(0)

        return SparseZIP64ByteSource(local: local, tailOffset: centralOffset, tail: tail)
    }

    private func storedPayloadOffset(name: String) -> Int {
        30 + Data(name.utf8).count
    }

    private func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { bytes in
            cZlib_crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
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
}

private struct DataByteSource: SVPPackageByteSource {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var length: UInt64 { UInt64(data.count) }

    func read(offset: UInt64, length: Int) throws -> Data {
        guard length >= 0 else { throw SVPPackageByteSourceError.invalidLength }
        let (end, overflow) = offset.addingReportingOverflow(UInt64(length))
        guard !overflow, end <= UInt64(data.count) else { throw SVPPackageByteSourceError.outOfRange }
        return Data(data[Int(offset)..<Int(end)])
    }
}

private final class RecordingDataByteSource: SVPPackageByteSource, @unchecked Sendable {
    let data: Data
    private(set) var maximumRequestedLength = 0

    init(_ data: Data) {
        self.data = data
    }

    var length: UInt64 { UInt64(data.count) }

    func resetMaximumRequestedLength() {
        maximumRequestedLength = 0
    }

    func read(offset: UInt64, length: Int) throws -> Data {
        maximumRequestedLength = max(maximumRequestedLength, length)
        return try DataByteSource(data).read(offset: offset, length: length)
    }
}

private final class SparseZIP64ByteSource: SVPPackageByteSource, @unchecked Sendable {
    let local: Data
    let tailOffset: UInt64
    let tail: Data
    private(set) var maximumRequestedLength = 0

    init(local: Data, tailOffset: UInt64, tail: Data) {
        self.local = local
        self.tailOffset = tailOffset
        self.tail = tail
    }

    var length: UInt64 { tailOffset + UInt64(tail.count) }

    func read(offset: UInt64, length: Int) throws -> Data {
        guard length >= 0 else { throw SVPPackageByteSourceError.invalidLength }
        let (end, overflow) = offset.addingReportingOverflow(UInt64(length))
        guard !overflow, end <= self.length else { throw SVPPackageByteSourceError.outOfRange }
        maximumRequestedLength = max(maximumRequestedLength, length)

        var result = Data(repeating: 0, count: length)
        overlay(local, segmentOffset: 0, requestOffset: offset, result: &result)
        overlay(tail, segmentOffset: tailOffset, requestOffset: offset, result: &result)
        return result
    }

    private func overlay(_ segment: Data, segmentOffset: UInt64, requestOffset: UInt64, result: inout Data) {
        let requestEnd = requestOffset + UInt64(result.count)
        let segmentEnd = segmentOffset + UInt64(segment.count)
        let overlapStart = max(requestOffset, segmentOffset)
        let overlapEnd = min(requestEnd, segmentEnd)
        guard overlapStart < overlapEnd else { return }

        let sourceStart = Int(overlapStart - segmentOffset)
        let destinationStart = Int(overlapStart - requestOffset)
        let count = Int(overlapEnd - overlapStart)
        result.replaceSubrange(
            destinationStart..<destinationStart + count,
            with: segment[sourceStart..<sourceStart + count]
        )
    }
}
