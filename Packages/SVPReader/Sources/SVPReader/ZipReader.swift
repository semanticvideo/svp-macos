import Foundation

final class ZipReader {
    private let centralDirEntries: [ZipCentralDirEntry]
    private let entryMap: [String: ZipCentralDirEntry]
    private let localEntryLocator: ZipLocalEntryLocator
    private let entryDecoder: ZipEntryDecoder
    private let entryExtractor: ZipEntryExtractor
    private let storedEntryRangeReader: ZipStoredEntryRangeReader

    convenience init(url: URL) throws {
        let fileSource: FilePackageByteSource
        do {
            fileSource = try FilePackageByteSource(url: url)
        } catch {
            throw ZipReaderError.fileOpenFailed("Cannot open file: \(url.path): \(error)")
        }
        try self.init(source: fileSource)
    }

    init(source: any SVPPackageByteSource) throws {
        let entries = try ZipArchiveIndex.parse(source: source, fileLength: source.length)
        guard Set(entries.map(\.fileName)).count == entries.count else {
            throw ZipReaderError.readFailed("ZIP central directory contains duplicate entry names")
        }
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.fileName, $0) })
        let localEntryLocator = ZipLocalEntryLocator(
            source: source,
            fileLength: source.length
        )

        self.centralDirEntries = entries
        self.entryMap = entryMap
        self.localEntryLocator = localEntryLocator
        self.entryDecoder = ZipEntryDecoder(
            source: source,
            localEntryLocator: localEntryLocator
        )
        self.entryExtractor = ZipEntryExtractor(
            source: source,
            localEntryLocator: localEntryLocator
        )
        self.storedEntryRangeReader = ZipStoredEntryRangeReader(
            source: source,
            entryMap: entryMap,
            localEntryLocator: localEntryLocator
        )
    }

    var entryNames: [String] {
        centralDirEntries.map { $0.fileName }
    }

    func hasEntry(_ name: String) -> Bool {
        entryMap[name] != nil
    }

    func entryInfo(_ name: String) -> ZipCentralDirEntry? {
        entryMap[name]
    }

    func readEntry(_ name: String) throws -> Data {
        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        return try entryDecoder.readEntryData(entry: entry)
    }

    func readEntryStream(_ name: String, bufferSize: Int = 65_536) throws -> Data {
        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        return try entryDecoder.readEntryData(entry: entry)
    }

    func extractEntry(
        _ name: String,
        to destinationURL: URL,
        bufferSize: Int = 1_048_576
    ) throws {
        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        try entryExtractor.extractEntry(entry, to: destinationURL, bufferSize: bufferSize)
    }

    func entryDataOffset(_ name: String) throws -> UInt64 {
        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        return try localEntryLocator.dataOffset(for: entry)
    }

    func readStoredEntryRange(
        _ name: String,
        offset: UInt64,
        length: Int
    ) throws -> Data {
        try storedEntryRangeReader.read(name, offset: offset, length: length)
    }

    static func inflate(data: Data, entry: ZipCentralDirEntry) throws -> Data {
        try ZipEntryDecoder.inflate(data: data, entry: entry)
    }
}
