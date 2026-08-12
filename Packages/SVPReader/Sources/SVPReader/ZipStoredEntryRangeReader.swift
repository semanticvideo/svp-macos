import Foundation

final class ZipStoredEntryRangeReader {
    private struct RangeInfo {
        let dataOffset: UInt64
        let size: UInt64
    }

    private let source: any SVPPackageByteSource
    private let entryMap: [String: ZipCentralDirEntry]
    private let localEntryLocator: ZipLocalEntryLocator
    private let rangeInfoLock = NSLock()
    private var rangeInfoCache: [String: RangeInfo] = [:]

    init(
        source: any SVPPackageByteSource,
        entryMap: [String: ZipCentralDirEntry],
        localEntryLocator: ZipLocalEntryLocator
    ) {
        self.source = source
        self.entryMap = entryMap
        self.localEntryLocator = localEntryLocator
    }

    func read(_ name: String, offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        let rangeInfo = try storedEntryRangeInfo(name)
        guard offset < rangeInfo.size else { return Data() }

        let bytesToRead = Int(min(UInt64(length), rangeInfo.size - offset))
        let dataOffset = try localEntryLocator.checkedAdd(rangeInfo.dataOffset, offset)
        return try source.read(offset: dataOffset, length: bytesToRead)
    }

    private func storedEntryRangeInfo(_ name: String) throws -> RangeInfo {
        rangeInfoLock.lock()
        defer { rangeInfoLock.unlock() }

        if let cached = rangeInfoCache[name] {
            return cached
        }

        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        guard entry.compressionMethod == 0 else {
            throw ZipReaderError.readFailed(
                "Cannot read byte ranges from compressed entry: \(name)"
            )
        }

        let rangeInfo = RangeInfo(
            dataOffset: try localEntryLocator.dataOffset(for: entry),
            size: entry.uncompressedSize
        )
        rangeInfoCache[name] = rangeInfo
        return rangeInfo
    }
}
