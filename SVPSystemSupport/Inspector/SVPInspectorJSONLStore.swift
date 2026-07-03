import Foundation
@_spi(Inspector) import SVPReader

nonisolated struct SVPInspectorJSONLSortValue: Comparable {
    let value: Any?

    static func < (lhs: SVPInspectorJSONLSortValue, rhs: SVPInspectorJSONLSortValue) -> Bool {
        if lhs.value == nil && rhs.value == nil { return false }
        if lhs.value == nil { return true }
        if rhs.value == nil { return false }

        if let lhsArray = lhs.value as? [Any], let rhsArray = rhs.value as? [Any] {
            return lhsArray.count < rhsArray.count
        }
        if let lhsNumber = lhs.value as? NSNumber, let rhsNumber = rhs.value as? NSNumber {
            return lhsNumber.doubleValue < rhsNumber.doubleValue
        }

        return String(describing: lhs.value!) < String(describing: rhs.value!)
    }

    static func == (lhs: SVPInspectorJSONLSortValue, rhs: SVPInspectorJSONLSortValue) -> Bool {
        if let lhsNumber = lhs.value as? NSNumber, let rhsNumber = rhs.value as? NSNumber {
            return lhsNumber.doubleValue == rhsNumber.doubleValue
        }
        return String(describing: lhs.value ?? "") == String(describing: rhs.value ?? "")
    }
}

nonisolated final class SVPInspectorJSONLStore: @unchecked Sendable {
    private static let cacheLimit = 512

    let entryName: String
    let rowCount: Int
    let uncompressedSize: UInt64?

    private let tempDirectoryURL: URL
    private let fileURL: URL
    private let readHandle: FileHandle
    private let lineOffsets: [UInt64]
    private let fileSize: UInt64
    private let readLock = NSLock()
    private let cacheLock = NSLock()
    private var rowCache: [Int: [String: Any]] = [:]
    private var cacheOrder: [Int] = []

    convenience init(packageURL: URL, entryName: String) throws {
        let reader = try SVPReader(url: packageURL)
        try reader.validateSVP()
        try self.init(reader: reader, entryName: entryName)
    }

    init(reader: SVPReader, entryName: String) throws {
        self.entryName = entryName

        let uncompressedSize = reader.entryUncompressedSize(entryName)
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-inspector-jsonl-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempDirectoryURL.appendingPathComponent(Self.safeFileName(for: entryName))

        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        do {
            let fileSize: UInt64
            let lineOffsets: [UInt64]

            if reader.hasEntry(entryName) {
                try reader.extractEntry(entryName, to: fileURL)
                fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
                lineOffsets = try Self.indexLineOffsets(fileURL: fileURL, fileSize: fileSize)
            } else {
                guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                    throw SVPInspectorJSONLStoreError.tempFileCreateFailed(fileURL.path)
                }
                fileSize = 0
                lineOffsets = []
            }

            self.uncompressedSize = uncompressedSize
            self.tempDirectoryURL = tempDirectoryURL
            self.fileURL = fileURL
            self.fileSize = fileSize
            self.lineOffsets = lineOffsets
            self.readHandle = try FileHandle(forReadingFrom: fileURL)
            self.rowCount = lineOffsets.count
        } catch {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
            throw error
        }
    }

    deinit {
        try? readHandle.close()
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    func row(at index: Int) -> [String: Any]? {
        guard index >= 0, index < rowCount else { return nil }
        if let cached = cachedRow(at: index) { return cached }

        guard let data = readLineData(at: index),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        cache(row, at: index)
        return row
    }

    func text(at index: Int, key: String) -> String {
        guard let row = row(at: index) else { return "—" }
        return Self.displayString(row, key)
    }

    func microsecondsText(at index: Int, key: String) -> String {
        guard let row = row(at: index) else { return "—" }
        return Self.formatMicroseconds(row, key)
    }

    func sortValue(at index: Int, key: String) -> SVPInspectorJSONLSortValue {
        SVPInspectorJSONLSortValue(value: row(at: index)?[key])
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

    private func cache(_ row: [String: Any], at index: Int) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard rowCache[index] == nil else { return }
        rowCache[index] = row
        cacheOrder.append(index)

        while cacheOrder.count > Self.cacheLimit {
            let removed = cacheOrder.removeFirst()
            rowCache[removed] = nil
        }
    }

    private func cachedRow(at index: Int) -> [String: Any]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return rowCache[index]
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

    private static func safeFileName(for entryName: String) -> String {
        entryName.replacingOccurrences(of: "/", with: "_")
    }

    private static func displayString(_ dict: [String: Any], _ key: String) -> String {
        guard let value = dict[key] else { return "—" }
        if let string = value as? String { return string.isEmpty ? "—" : string }
        if let number = value as? NSNumber { return number.stringValue }
        if let array = value as? [Any] { return "\(array.count) items" }
        if let dict = value as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: data, encoding: .utf8) { return string }
            return String(describing: dict)
        }
        return String(describing: value)
    }

    private static func formatMicroseconds(_ dict: [String: Any], _ key: String) -> String {
        guard let number = dict[key] as? NSNumber else { return "—" }
        return String(format: "%.3f", number.doubleValue / 1_000_000)
    }
}

nonisolated enum SVPInspectorJSONLStoreError: Error {
    case tempFileCreateFailed(String)
}
