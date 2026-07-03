import Foundation
import SVPReader

nonisolated struct SVPRelationshipRow {
    let sourceID: String
    let type: String
    let targetID: String
    let startText: String
    let endText: String
    let confidence: String
}

nonisolated final class SVPRelationshipJSONLStore: @unchecked Sendable {
    private static let entryName = "relationships/relationships.jsonl"
    private static let cacheLimit = 512

    let rowCount: Int
    let uncompressedSize: UInt64?

    private let tempDirectoryURL: URL
    private let fileURL: URL
    private let readHandle: FileHandle
    private let lineOffsets: [UInt64]
    private let fileSize: UInt64
    private let readLock = NSLock()
    private var rowCache: [Int: SVPRelationshipRow] = [:]
    private var cacheOrder: [Int] = []

    init(packageURL: URL) throws {
        let reader = try SVPReader(url: packageURL)
        try reader.validateSVP()

        self.uncompressedSize = reader.entryUncompressedSize(Self.entryName)
        self.tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-relationships-\(UUID().uuidString)", isDirectory: true)
        self.fileURL = tempDirectoryURL.appendingPathComponent("relationships.jsonl")

        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        if reader.hasEntry(Self.entryName) {
            try reader.extractEntry(Self.entryName, to: fileURL)
            self.fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
            self.lineOffsets = try Self.indexLineOffsets(fileURL: fileURL, fileSize: fileSize)
        } else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            self.fileSize = 0
            self.lineOffsets = []
        }

        self.readHandle = try FileHandle(forReadingFrom: fileURL)
        self.rowCount = lineOffsets.count
    }

    deinit {
        try? readHandle.close()
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    func row(at index: Int) -> SVPRelationshipRow? {
        guard index >= 0, index < rowCount else { return nil }
        if let cached = rowCache[index] { return cached }

        guard let data = readLineData(at: index),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let row = SVPRelationshipRow(
            sourceID: displayValue(json["source_id"]),
            type: displayValue(json["type"]),
            targetID: displayValue(json["target_id"]),
            startText: microsecondsValue(json["start_us"]),
            endText: microsecondsValue(json["end_us"]),
            confidence: displayValue(json["confidence"])
        )
        cache(row, at: index)
        return row
    }

    private func readLineData(at index: Int) -> Data? {
        let start = lineOffsets[index]
        let end = index + 1 < lineOffsets.count ? lineOffsets[index + 1] : fileSize
        guard end > start else { return nil }

        let byteCount = Int(end - start)

        readLock.lock()
        defer { readLock.unlock() }
        do {
            try readHandle.seek(toOffset: start)
            guard var data = try readHandle.read(upToCount: byteCount) else { return nil }
            while let last = data.last, last == 10 || last == 13 {
                data.removeLast()
            }
            return data
        } catch {
            return nil
        }
    }

    private func cache(_ row: SVPRelationshipRow, at index: Int) {
        guard rowCache[index] == nil else { return }
        rowCache[index] = row
        cacheOrder.append(index)

        while cacheOrder.count > Self.cacheLimit {
            let removed = cacheOrder.removeFirst()
            rowCache[removed] = nil
        }
    }

    private static func indexLineOffsets(fileURL: URL, fileSize: UInt64) throws -> [UInt64] {
        guard fileSize > 0 else { return [] }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offsets: [UInt64] = [0]
        var absoluteOffset: UInt64 = 0
        let chunkSize = 1_048_576

        while autoreleasepool(invoking: {
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                return false
            }

            for (index, byte) in chunk.enumerated() where byte == 10 {
                offsets.append(absoluteOffset + UInt64(index) + 1)
            }
            absoluteOffset += UInt64(chunk.count)
            return true
        }) {}

        if offsets.last == fileSize {
            offsets.removeLast()
        }
        return offsets
    }

    private func displayValue(_ value: Any?) -> String {
        guard let value else { return "—" }
        if let string = value as? String { return string.isEmpty ? "—" : string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private func microsecondsValue(_ value: Any?) -> String {
        guard let number = value as? NSNumber else { return "—" }
        return String(format: "%.3f", number.doubleValue / 1_000_000)
    }
}
