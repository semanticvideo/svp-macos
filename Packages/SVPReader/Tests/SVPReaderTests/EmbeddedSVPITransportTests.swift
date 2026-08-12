import XCTest
@testable import SVPReader

final class EmbeddedSVPITransportTests: XCTestCase {
    private let samplePayload = Data("embedded-svpi-payload".utf8)

    func testSupportedBrandFamilies() throws {
        let cases: [(String, ISOBaseMediaFamily)] = [("mp42", .mp4), ("qt  ", .quickTime), ("M4V ", .m4v), ("M4A ", .m4a), ("M4P ", .m4a)]
        for (brand, family) in cases {
            let source = MemorySource(ftyp(brand: brand) + box(type: "free", payload: Data()))
            XCTAssertEqual(try ISOBMFFScanner.scan(source: source)?.family, family)
        }
    }

    func testUnregisteredBrandPrefixesRemainUnsupported() throws {
        for brand in ["isox", "cmfZ"] {
            XCTAssertNil(try ISOBMFFScanner.scan(source: MemorySource(ftyp(brand: brand))))
        }
    }

    func testExtendedSizeLeadingFtypIsAccepted() throws {
        let payload = Data("mp42".utf8) + be32(0) + Data("mp42".utf8)
        let extendedFtyp = be32(1) + Data("ftyp".utf8) + be64(UInt64(16 + payload.count)) + payload
        let scan = try ISOBMFFScanner.scan(source: MemorySource(extendedFtyp + box(type: "free", payload: Data())))
        XCTAssertEqual(scan?.majorBrand, "mp42")
        XCTAssertEqual(scan?.family, .mp4)
    }

    func testSupportedMediaWithoutEmbedding() throws {
        let url = try write(ftyp(brand: "mp42") + box(type: "mdat", payload: Data(repeating: 7, count: 64)))
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .noEmbeddedSvpi = SemanticMediaResolver.resolve(url: url) else { return XCTFail("Expected noEmbeddedSvpi") }
    }

    func testValidEmbeddingAndUnrelatedUUID() throws {
        let media = try embeddedMedia(payload: samplePayload, prefix: uuidBox(userType: Data(repeating: 1, count: 16), content: Data()))
        let source = MemorySource(media)
        let scan = try XCTUnwrap(ISOBMFFScanner.scan(source: source))
        let candidate = try XCTUnwrap(scan.embeddingCandidates.first)
        let envelope = try EmbeddedSVPIEnvelopeParser.parse(candidate: candidate, source: source)
        let payload = try BoundedPackageByteSource(source: source, baseOffset: envelope.payloadOffset, length: envelope.payloadLength)

        XCTAssertEqual(scan.family, .mp4)
        XCTAssertEqual(scan.embeddingCandidates.count, 1)
        XCTAssertEqual(try payload.read(offset: 0, length: Int(payload.length)), samplePayload)
        XCTAssertNoThrow(try EmbeddedSVPIIntegrityVerifier.verify(source: payload, expectedHash: envelope.expectedHash))
    }

    func testExtendedSizeEmbedding() throws {
        let content = try envelope(payload: samplePayload) + samplePayload
        let extended = be32(1) + Data("uuid".utf8) + be64(UInt64(32 + content.count)) + EmbeddedSVPITransportProfile.uuid + content
        let source = MemorySource(ftyp(brand: "qt  ") + extended)
        let scan = try XCTUnwrap(ISOBMFFScanner.scan(source: source))
        let parsed = try EmbeddedSVPIEnvelopeParser.parse(
            candidate: try XCTUnwrap(scan.embeddingCandidates.first),
            source: source
        )

        XCTAssertEqual(scan.family, .quickTime)
        XCTAssertEqual(parsed.profileVersion, EmbeddedSVPITransportProfile.version)
        XCTAssertEqual(parsed.payloadLength, UInt64(samplePayload.count))
    }

    func testDuplicateEmbeddings() throws {
        let one = try embeddingBox(payload: samplePayload)
        let url = try write(ftyp(brand: "mp42") + one + one); defer { try? FileManager.default.removeItem(at: url) }
        guard case .invalidEmbedding(.duplicateEmbeddings) = SemanticMediaResolver.resolve(url: url) else { return XCTFail("Expected duplicate error") }
    }

    func testEnvelopeVersionFlagsLengthAndHashFailures() throws {
        try assertInvalid(mutateEnvelope(payload: samplePayload) { $0.replaceSubrange(8..<10, with: be16(2)) }, matches: { if case .unsupportedVersion = $0 { true } else { false } })
        try assertInvalid(mutateEnvelope(payload: samplePayload) { $0.replaceSubrange(12..<16, with: be32(1)) }, matches: { if case .unsupportedFlags = $0 { true } else { false } })
        try assertInvalid(mutateEnvelope(payload: samplePayload) { $0.replaceSubrange(16..<24, with: be64(UInt64(samplePayload.count + 1))) }, matches: { if case .payloadLengthMismatch = $0 { true } else { false } })
        var damaged = samplePayload; damaged[0] ^= 0xff
        let goodEnvelope = try envelope(payload: samplePayload)
        try assertInvalid(uuidBox(userType: EmbeddedSVPITransportProfile.uuid, content: goodEnvelope + damaged), matches: { $0 == .payloadHashMismatch })
    }

    func testTruncatedEnvelopeAndBoxHeadersAndInvalidSizes() throws {
        try assertInvalid(uuidBox(userType: EmbeddedSVPITransportProfile.uuid, content: Data(repeating: 0, count: 20)), matches: { if case .truncatedUUIDBox = $0 { true } else { false } })
        try assertScannerError(ftyp(brand: "mp42") + Data([0, 0, 0]), matches: { if case .truncatedBoxHeader = $0 { true } else { false } })
        try assertScannerError(ftyp(brand: "mp42") + be32(4) + Data("free".utf8), matches: { if case .invalidBoxSize = $0 { true } else { false } })
        try assertScannerError(ftyp(brand: "mp42") + be32(1) + Data("free".utf8) + be64(8), matches: { if case .invalidBoxSize = $0 { true } else { false } })
        try assertScannerError(ftyp(brand: "mp42") + be32(0) + Data("free".utf8), matches: { if case .zeroSizedTopLevelBox = $0 { true } else { false } })
    }

    func testEnvelopePayloadOutsidePhysicalSourceIsRejected() throws {
        let payload = Data([1])
        let envelopeData = try envelope(payload: payload)
        let candidate = ISOBMFFEmbeddingCandidate(boxOffset: 0, boxSize: 89, contentOffset: 0, contentSize: 65)
        XCTAssertThrowsError(try EmbeddedSVPIEnvelopeParser.parse(candidate: candidate, source: MemorySource(envelopeData))) { error in
            XCTAssertEqual(error as? EmbeddedSVPIError, .payloadOutOfBounds)
        }
    }

    func testTopLevelOffsetOverflowIsRejected() {
        let prefix = ftyp(brand: "mp42")
        let source = SparseHeaderSource(prefix: prefix, secondHeader: be32(1) + Data("mdat".utf8) + be64(UInt64.max))
        XCTAssertThrowsError(try ISOBMFFScanner.scan(source: source)) { error in
            guard case .arithmeticOverflow = error as? EmbeddedSVPIError else { return XCTFail("Expected arithmetic overflow, got \(error)") }
        }
    }

    func testBoundedSourceRejectsUnderflowOverflowAndOutOfRange() throws {
        let source = MemorySource(Data(0..<32))
        XCTAssertThrowsError(try BoundedPackageByteSource(source: source, baseOffset: 30, length: 3))
        let bounded = try BoundedPackageByteSource(source: source, baseOffset: 8, length: 8)
        XCTAssertThrowsError(try bounded.read(offset: 7, length: 2))
        XCTAssertThrowsError(try bounded.read(offset: UInt64.max, length: 1))
        XCTAssertEqual(try bounded.read(offset: 0, length: 8), Data(8..<16))
    }

    func testScannerSeeksAcrossLargeSparseMdat() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close(); try? FileManager.default.removeItem(at: url) }
        let total: UInt64 = 1_073_741_824
        let fileType = ftyp(brand: "mp42")
        try handle.write(contentsOf: fileType)
        try handle.write(contentsOf: be32(1) + Data("mdat".utf8) + be64(total - UInt64(fileType.count)))
        try handle.truncate(atOffset: total)
        let scan = try ISOBMFFScanner.scan(source: FilePackageByteSource(url: url))
        XCTAssertEqual(scan?.topLevelBoxCount, 2)
        XCTAssertLessThan(scan?.headerBytesRead ?? .max, 128)
    }

    private func assertInvalid(_ embedding: Data, matches: (EmbeddedSVPIError) -> Bool) throws {
        let url = try write(ftyp(brand: "mp42") + embedding); defer { try? FileManager.default.removeItem(at: url) }
        guard case .invalidEmbedding(let error) = SemanticMediaResolver.resolve(url: url), matches(error) else { return XCTFail("Unexpected status") }
    }
    private func assertScannerError(_ data: Data, matches: (EmbeddedSVPIError) -> Bool) throws {
        XCTAssertThrowsError(try ISOBMFFScanner.scan(source: MemorySource(data))) { error in XCTAssertTrue((error as? EmbeddedSVPIError).map(matches) ?? false) }
    }
    private func embeddedMedia(payload: Data, prefix: Data = Data()) throws -> Data { ftyp(brand: "mp42") + prefix + (try embeddingBox(payload: payload)) }
    private func embeddingBox(payload: Data) throws -> Data { uuidBox(userType: EmbeddedSVPITransportProfile.uuid, content: try envelope(payload: payload) + payload) }
    private func mutateEnvelope(payload: Data, mutation: (inout Data) -> Void) throws -> Data { var value = try envelope(payload: payload); mutation(&value); return uuidBox(userType: EmbeddedSVPITransportProfile.uuid, content: value + payload) }
    private func envelope(payload: Data) throws -> Data { var data = EmbeddedSVPITransportProfile.magic + be16(1) + be16(64) + be32(0) + be64(UInt64(payload.count)); data += try EmbeddedSVPIIntegrityVerifier.digest(source: MemorySource(payload)); data += Data(repeating: 0, count: 8); return data }
    private func ftyp(brand: String) -> Data { box(type: "ftyp", payload: Data(brand.utf8) + be32(0) + Data(brand.utf8)) }
    private func uuidBox(userType: Data, content: Data) -> Data { be32(UInt32(24 + content.count)) + Data("uuid".utf8) + userType + content }
    private func box(type: String, payload: Data) -> Data { be32(UInt32(8 + payload.count)) + Data(type.utf8) + payload }
    private func write(_ data: Data) throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try data.write(to: url); return url }
    private func be16(_ value: UInt16) -> Data { Data([UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
    private func be32(_ value: UInt32) -> Data { Data([UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
    private func be64(_ value: UInt64) -> Data { Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) }) }
}

private struct MemorySource: SVPPackageByteSource {
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    var length: UInt64 { UInt64(bytes.count) }
    func read(offset: UInt64, length: Int) throws -> Data {
        guard length >= 0, offset <= UInt64(bytes.count) else { throw SVPPackageByteSourceError.outOfRange }
        let (end, overflow) = offset.addingReportingOverflow(UInt64(length))
        guard !overflow, end <= UInt64(bytes.count) else { throw SVPPackageByteSourceError.outOfRange }
        return Data(bytes[Int(offset)..<Int(end)])
    }
}

private struct SparseHeaderSource: SVPPackageByteSource {
    let prefix: Data
    let secondHeader: Data
    var length: UInt64 { UInt64.max }
    func read(offset: UInt64, length: Int) throws -> Data {
        if offset == 0 { return Data(prefix.prefix(length)) }
        if offset == UInt64(prefix.count) { return Data(secondHeader.prefix(length)) }
        if offset == UInt64(prefix.count + 8) { return Data(secondHeader.dropFirst(8).prefix(length)) }
        throw SVPPackageByteSourceError.outOfRange
    }
}
