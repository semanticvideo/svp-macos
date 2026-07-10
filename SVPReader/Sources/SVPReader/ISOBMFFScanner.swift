import Foundation

public struct ISOBMFFEmbeddingCandidate: Sendable {
    public let boxOffset: UInt64
    public let boxSize: UInt64
    public let contentOffset: UInt64
    public let contentSize: UInt64
}

public struct ISOBMFFScanResult: Sendable {
    public let family: ISOBaseMediaFamily
    public let majorBrand: String
    public let compatibleBrands: [String]
    public let embeddingCandidates: [ISOBMFFEmbeddingCandidate]
    public let topLevelBoxCount: Int
    public let headerBytesRead: UInt64
}

public enum ISOBMFFScanner {
    public static func scan(source: any SVPPackageByteSource) throws -> ISOBMFFScanResult? {
        guard source.length >= 8 else { return nil }
        let first = try source.read(offset: 0, length: 8)
        guard ascii(first, 4) == "ftyp" else { return nil }
        let firstSize = UInt64(be32(first, 0))
        guard firstSize != 0, firstSize != 1, firstSize >= 16, firstSize <= source.length, firstSize <= 1_048_576 else {
            throw EmbeddedSVPIError.malformedContainer("The leading ftyp box is invalid.")
        }
        let ftyp = try source.read(offset: 0, length: Int(firstSize))
        let majorBrand = ascii(ftyp, 8)
        var compatibleBrands: [String] = []
        if ftyp.count > 16 {
            var position = 16
            while position + 4 <= ftyp.count {
                compatibleBrands.append(ascii(ftyp, position))
                position += 4
            }
            guard position == ftyp.count else { throw EmbeddedSVPIError.malformedContainer("The ftyp compatible-brand list is misaligned.") }
        }
        guard let family = classify(brands: [majorBrand] + compatibleBrands) else { return nil }

        var candidates: [ISOBMFFEmbeddingCandidate] = []
        var offset: UInt64 = 0
        var count = 0
        var bytesRead: UInt64 = UInt64(ftyp.count)
        while offset < source.length {
            let remaining = source.length - offset
            guard remaining >= 8 else { throw EmbeddedSVPIError.truncatedBoxHeader(offset: offset) }
            let header = try source.read(offset: offset, length: 8)
            bytesRead += 8
            let compactSize = be32(header, 0)
            let type = ascii(header, 4)
            var boxSize: UInt64
            var headerSize: UInt64 = 8
            if compactSize == 1 {
                guard remaining >= 16 else { throw EmbeddedSVPIError.truncatedBoxHeader(offset: offset) }
                let extendedOffset = try checkedAdd(offset, 8, at: offset)
                let extended = try source.read(offset: extendedOffset, length: 8)
                bytesRead += 8
                boxSize = be64(extended, 0)
                headerSize = 16
                guard boxSize >= 16 else { throw EmbeddedSVPIError.invalidBoxSize(offset: offset) }
            } else if compactSize == 0 {
                throw EmbeddedSVPIError.zeroSizedTopLevelBox(offset: offset)
            } else {
                boxSize = UInt64(compactSize)
                guard boxSize >= 8 else { throw EmbeddedSVPIError.invalidBoxSize(offset: offset) }
            }
            let (boxEnd, overflow) = offset.addingReportingOverflow(boxSize)
            guard !overflow else { throw EmbeddedSVPIError.arithmeticOverflow(offset: offset) }
            guard boxEnd <= source.length else { throw EmbeddedSVPIError.invalidBoxSize(offset: offset) }
            if type == "uuid" {
                let (uuidHeaderSize, sizeOverflow) = headerSize.addingReportingOverflow(16)
                guard !sizeOverflow, boxSize >= uuidHeaderSize else { throw EmbeddedSVPIError.truncatedUUIDBox(offset: offset) }
                let (uuidOffset, offsetOverflow) = offset.addingReportingOverflow(headerSize)
                guard !offsetOverflow else { throw EmbeddedSVPIError.arithmeticOverflow(offset: offset) }
                let userType = try source.read(offset: uuidOffset, length: 16)
                bytesRead += 16
                if userType == EmbeddedSVPITransportProfile.uuid {
                    let contentOffset = try checkedAdd(uuidOffset, 16, at: offset)
                    candidates.append(.init(boxOffset: offset, boxSize: boxSize, contentOffset: contentOffset, contentSize: boxSize - uuidHeaderSize))
                }
            }
            count += 1
            offset = boxEnd
        }
        return ISOBMFFScanResult(family: family, majorBrand: majorBrand, compatibleBrands: compatibleBrands, embeddingCandidates: candidates, topLevelBoxCount: count, headerBytesRead: bytesRead)
    }

    private static func classify(brands: [String]) -> ISOBaseMediaFamily? {
        if brands.contains("qt  ") { return .quickTime }
        if brands.contains("M4V ") || brands.contains("M4VH") || brands.contains("M4VP") { return .m4v }
        if brands.contains("M4A ") || brands.contains("M4B ") { return .m4a }
        let exact: Set<String> = ["isom", "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9", "mp41", "mp42", "avc1", "dash", "cmfc", "cmfs", "cmff", "cmfl"]
        if brands.contains(where: { exact.contains($0) || $0.hasPrefix("iso") || $0.hasPrefix("cmf") }) { return .mp4 }
        return nil
    }

    private static func ascii(_ data: Data, _ offset: Int) -> String { String(bytes: data[offset..<offset + 4], encoding: .ascii) ?? "" }
    private static func checkedAdd(_ lhs: UInt64, _ rhs: UInt64, at offset: UInt64) throws -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw EmbeddedSVPIError.arithmeticOverflow(offset: offset) }
        return sum
    }
    static func be16(_ data: Data, _ offset: Int) -> UInt16 { data[offset..<offset + 2].reduce(0) { ($0 << 8) | UInt16($1) } }
    static func be32(_ data: Data, _ offset: Int) -> UInt32 { data[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) } }
    static func be64(_ data: Data, _ offset: Int) -> UInt64 { data[offset..<offset + 8].reduce(0) { ($0 << 8) | UInt64($1) } }
}
