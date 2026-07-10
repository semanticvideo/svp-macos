import Foundation
import CZlib
import Darwin

struct ZipCentralDirEntry {
    let fileName: String
    let compressionMethod: UInt16
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let localHeaderOffset: UInt64
    let crc32: UInt32
}

struct ZipLocalHeader {
    let compressionMethod: UInt16
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let fileNameLength: UInt16
    let extraFieldLength: UInt16
    let dataOffset: UInt64
}

enum ZipReaderError: Error {
    case fileOpenFailed(String)
    case notZipArchive
    case readFailed(String)
    case inflateFailed(String)
    case entryNotFound(String)
}

final class ZipReader {
    private struct StoredEntryRangeInfo {
        let dataOffset: UInt64
        let size: UInt64
    }

    private let source: any SVPPackageByteSource
    private let rangeInfoLock = NSLock()
    private var storedEntryRangeInfoCache: [String: StoredEntryRangeInfo] = [:]
    private let fileLength: UInt64
    private let centralDirEntries: [ZipCentralDirEntry]
    private let entryMap: [String: ZipCentralDirEntry]

    convenience init(url: URL) throws {
        let fileSource: FilePackageByteSource
        do { fileSource = try FilePackageByteSource(url: url) }
        catch { throw ZipReaderError.fileOpenFailed("Cannot open file: \(url.path): \(error)") }
        try self.init(source: fileSource)
    }

    init(source: any SVPPackageByteSource) throws {
        self.source = source
        self.fileLength = source.length
        let entries = try Self.parseCentralDirectory(source: source, fileLength: source.length)
        guard Set(entries.map(\.fileName)).count == entries.count else {
            throw ZipReaderError.readFailed("ZIP central directory contains duplicate entry names")
        }
        self.centralDirEntries = entries
        self.entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.fileName, $0) })
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
        return try readEntryData(entry: entry)
    }

    func readEntryStream(_ name: String, bufferSize: Int = 65536) throws -> Data {
        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        return try readEntryData(entry: entry)
    }

    func extractEntry(_ name: String, to destinationURL: URL, bufferSize: Int = 1_048_576) throws {
        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        try extractEntryData(entry: entry, to: destinationURL, bufferSize: bufferSize)
    }

    func entryDataOffset(_ name: String) throws -> UInt64 {
        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        let localHeader = try readLocalHeader(offset: entry.localHeaderOffset)
        return try checkedAdd(entry.localHeaderOffset, localHeader.dataOffset)
    }

    func readStoredEntryRange(_ name: String, offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        let rangeInfo = try storedEntryRangeInfo(name)
        let entrySize = rangeInfo.size
        guard offset < entrySize else { return Data() }

        let bytesToRead = Int(min(UInt64(length), entrySize - offset))
        let dataOffset = try checkedAdd(rangeInfo.dataOffset, offset)
        return try source.read(offset: dataOffset, length: bytesToRead)
    }

    private func readEntryData(entry: ZipCentralDirEntry) throws -> Data {
        let localHeader = try readLocalHeader(offset: entry.localHeaderOffset)

        let dataOffset = try checkedAdd(entry.localHeaderOffset, localHeader.dataOffset)

        if entry.compressionMethod == 0 {
            let size = resolveSize(local: localHeader, central: entry)
            guard size <= UInt64(Int.max) else { throw ZipReaderError.readFailed("Entry is too large") }
            let data = try source.read(offset: dataOffset, length: Int(size))
            return data
        } else if entry.compressionMethod == 8 {
            let compressedSize = resolveCompressedSize(local: localHeader, central: entry)
            guard compressedSize <= UInt64(Int.max) else { throw ZipReaderError.readFailed("Compressed entry is too large") }
            let compressedData = try source.read(offset: dataOffset, length: Int(compressedSize))
            return try Self.inflate(data: compressedData, expectedSize: entry.uncompressedSize)
        } else {
            throw ZipReaderError.readFailed("Unsupported compression method: \(entry.compressionMethod)")
        }
    }

    private func extractEntryData(entry: ZipCentralDirEntry, to destinationURL: URL, bufferSize: Int) throws {
        let localHeader = try readLocalHeader(offset: entry.localHeaderOffset)
        let dataOffset = try checkedAdd(entry.localHeaderOffset, localHeader.dataOffset)

        try? FileManager.default.removeItem(at: destinationURL)
        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ZipReaderError.readFailed("Cannot create destination: \(destinationURL.path)")
        }
        guard let outputHandle = try? FileHandle(forWritingTo: destinationURL) else {
            throw ZipReaderError.readFailed("Cannot open destination: \(destinationURL.path)")
        }
        defer {
            try? outputHandle.close()
        }

        if entry.compressionMethod == 0 {
            let size = resolveSize(local: localHeader, central: entry)
            try copyStoredEntry(offset: dataOffset, byteCount: size, to: outputHandle, bufferSize: bufferSize)
        } else if entry.compressionMethod == 8 {
            let compressedSize = resolveCompressedSize(local: localHeader, central: entry)
            try inflateEntry(offset: dataOffset, compressedByteCount: compressedSize, to: outputHandle, bufferSize: bufferSize)
        } else {
            throw ZipReaderError.readFailed("Unsupported compression method: \(entry.compressionMethod)")
        }
    }

    private func copyStoredEntry(offset: UInt64, byteCount: UInt64, to outputHandle: FileHandle, bufferSize: Int) throws {
        var remaining = byteCount
        var position = offset
        while remaining > 0 {
            let toRead = Int(min(UInt64(bufferSize), remaining))
            let chunk = try source.read(offset: position, length: toRead)
            outputHandle.write(chunk)
            remaining -= UInt64(chunk.count)
            position = try checkedAdd(position, UInt64(chunk.count))
        }
    }

    private func inflateEntry(offset: UInt64, compressedByteCount: UInt64, to outputHandle: FileHandle, bufferSize: Int) throws {
        let stream = cZlib_inflate_init()
        guard stream != nil else {
            throw ZipReaderError.inflateFailed("inflate init failed")
        }
        defer { cZlib_inflate_end(stream) }

        let inputChunkSize = max(1, bufferSize)
        let outputChunkSize = 65_536
        var remaining = compressedByteCount
        var position = offset
        var outputBuffer = [UInt8](repeating: 0, count: outputChunkSize)

        while remaining > 0 {
            let toRead = Int(min(UInt64(inputChunkSize), remaining))
            let chunk = try source.read(offset: position, length: toRead)

            var inputOffset = 0
            while inputOffset < chunk.count {
                var consumed = 0
                var produced = 0

                let result = chunk.withUnsafeBytes { inputPtr in
                    outputBuffer.withUnsafeMutableBufferPointer { outputPtr in
                        cZlib_inflate_process(
                            stream,
                            inputPtr.baseAddress?.advanced(by: inputOffset),
                            chunk.count - inputOffset,
                            outputPtr.baseAddress,
                            outputChunkSize,
                            &consumed,
                            &produced
                        )
                    }
                }

                if result < 0 {
                    throw ZipReaderError.inflateFailed("inflate process failed")
                }

                if produced > 0 {
                    outputHandle.write(Data(outputBuffer[0..<produced]))
                }

                inputOffset += consumed

                if consumed == 0 && produced == 0 {
                    break
                }
            }

            remaining -= UInt64(chunk.count)
            position = try checkedAdd(position, UInt64(chunk.count))
        }
    }

    private func storedEntryRangeInfo(_ name: String) throws -> StoredEntryRangeInfo {
        rangeInfoLock.lock()
        defer { rangeInfoLock.unlock() }

        if let cached = storedEntryRangeInfoCache[name] {
            return cached
        }

        guard let entry = entryMap[name] else {
            throw ZipReaderError.entryNotFound(name)
        }
        guard entry.compressionMethod == 0 else {
            throw ZipReaderError.readFailed("Cannot read byte ranges from compressed entry: \(name)")
        }

        let localHeader = try readLocalHeader(offset: entry.localHeaderOffset)
        let rangeInfo = StoredEntryRangeInfo(
            dataOffset: try checkedAdd(entry.localHeaderOffset, localHeader.dataOffset),
            size: resolveSize(local: localHeader, central: entry)
        )

        storedEntryRangeInfoCache[name] = rangeInfo

        return rangeInfo
    }


    private func resolveSize(local: ZipLocalHeader, central: ZipCentralDirEntry) -> UInt64 {
        if local.uncompressedSize != 0, local.uncompressedSize != UInt64(UInt32.max) { return local.uncompressedSize }
        return central.uncompressedSize
    }

    private func resolveCompressedSize(local: ZipLocalHeader, central: ZipCentralDirEntry) -> UInt64 {
        if local.compressedSize != 0, local.compressedSize != UInt64(UInt32.max) { return local.compressedSize }
        return central.compressedSize
    }

    private func readLocalHeader(offset: UInt64) throws -> ZipLocalHeader {
        let headerData = try source.read(offset: offset, length: 30)
        guard headerData.count >= 30 else {
            throw ZipReaderError.readFailed("Local header too short")
        }

        let signature = headerData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard signature == 0x04034b50 else {
            throw ZipReaderError.readFailed("Invalid local file header signature")
        }

        let compressionMethod = headerData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt16.self) }
        let compressedSize = headerData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 18, as: UInt32.self) }
        let uncompressedSize = headerData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 22, as: UInt32.self) }
        let fileNameLength = headerData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 26, as: UInt16.self) }
        let extraFieldLength = headerData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt16.self) }

        let dataOffset = UInt64(30) + UInt64(fileNameLength) + UInt64(extraFieldLength)

        return ZipLocalHeader(
            compressionMethod: compressionMethod,
            compressedSize: UInt64(compressedSize),
            uncompressedSize: UInt64(uncompressedSize),
            fileNameLength: fileNameLength,
            extraFieldLength: extraFieldLength,
            dataOffset: dataOffset
        )
    }

    private static func parseCentralDirectory(source: any SVPPackageByteSource, fileLength: UInt64) throws -> [ZipCentralDirEntry] {
        let eocd = try findEndOfCentralDirectory(source: source, fileLength: fileLength)
        var entries: [ZipCentralDirEntry] = []
        let centralDirectoryEnd = try checkedAdd(eocd.centralDirOffset, eocd.centralDirSize)
        guard centralDirectoryEnd <= eocd.recordOffset else {
            throw ZipReaderError.readFailed("ZIP central directory overlaps end records")
        }
        var offset = eocd.centralDirOffset

        while offset < centralDirectoryEnd {
            guard centralDirectoryEnd - offset >= 46 else {
                throw ZipReaderError.readFailed("ZIP central directory record is truncated")
            }
            let header = try source.read(offset: offset, length: 46)
            guard le32(header, 0) == 0x02014b50 else {
                throw ZipReaderError.readFailed("Invalid ZIP central directory signature")
            }

            let compressionMethod = le16(header, 10)
            let crc32 = le32(header, 16)
            let compactCompressedSize = le32(header, 20)
            let compactUncompressedSize = le32(header, 24)
            let fileNameLength = UInt64(le16(header, 28))
            let extraFieldLength = UInt64(le16(header, 30))
            let fileCommentLength = UInt64(le16(header, 32))
            let compactDiskStart = le16(header, 34)
            let compactLocalHeaderOffset = le32(header, 42)
            let variableLength = try checkedAdd(try checkedAdd(fileNameLength, extraFieldLength), fileCommentLength)
            let recordLength = try checkedAdd(46, variableLength)
            let recordEnd = try checkedAdd(offset, recordLength)
            guard recordEnd <= centralDirectoryEnd else {
                throw ZipReaderError.readFailed("ZIP central directory record extends outside its declared range")
            }

            let fileNameOffset = try checkedAdd(offset, 46)
            let fileNameData = try source.read(offset: fileNameOffset, length: Int(fileNameLength))
            guard let fileName = String(data: fileNameData, encoding: .utf8), !fileName.isEmpty else {
                throw ZipReaderError.readFailed("ZIP entry name is empty or invalid UTF-8")
            }
            let extraOffset = try checkedAdd(fileNameOffset, fileNameLength)
            let extra = try source.read(offset: extraOffset, length: Int(extraFieldLength))
            let resolved = try resolveZIP64Values(
                extra: extra,
                compressedSize: compactCompressedSize,
                uncompressedSize: compactUncompressedSize,
                localHeaderOffset: compactLocalHeaderOffset,
                diskStart: compactDiskStart
            )
            guard resolved.diskStart == 0 else {
                throw ZipReaderError.readFailed("Multi-disk ZIP packages are unsupported")
            }

            entries.append(ZipCentralDirEntry(
                fileName: fileName,
                compressionMethod: compressionMethod,
                compressedSize: resolved.compressedSize,
                uncompressedSize: resolved.uncompressedSize,
                localHeaderOffset: resolved.localHeaderOffset,
                crc32: crc32
            ))
            guard UInt64(entries.count) <= eocd.entryCount else {
                throw ZipReaderError.readFailed("ZIP central directory contains more entries than declared")
            }
            offset = recordEnd
        }
        guard offset == centralDirectoryEnd, UInt64(entries.count) == eocd.entryCount else {
            throw ZipReaderError.readFailed("ZIP central directory entry count does not match its end record")
        }
        return entries
    }

    private struct EOCD {
        let centralDirOffset: UInt64
        let centralDirSize: UInt64
        let entryCount: UInt64
        let recordOffset: UInt64
    }

    private static func findEndOfCentralDirectory(source: any SVPPackageByteSource, fileLength: UInt64) throws -> EOCD {
        let maxScan = min(UInt64(65557), fileLength)
        let scanStart = fileLength - maxScan
        let scanData = try source.read(offset: scanStart, length: Int(maxScan))

        guard scanData.count >= 22 else { throw ZipReaderError.notZipArchive }

        for i in stride(from: scanData.count - 22, through: 0, by: -1) {
            guard le32(scanData, i) == 0x06054b50 else { continue }
            let commentLength = UInt64(le16(scanData, i + 20))
            let recordOffset = try checkedAdd(scanStart, UInt64(i))
            guard try checkedAdd(recordOffset, try checkedAdd(22, commentLength)) == fileLength else { continue }
            let diskNumber = le16(scanData, i + 4)
            let centralDirectoryDisk = le16(scanData, i + 6)
            let entriesOnDisk = le16(scanData, i + 8)
            let totalEntries = le16(scanData, i + 10)
            let centralDirectorySize = le32(scanData, i + 12)
            let centralDirectoryOffset = le32(scanData, i + 16)

            let needsZIP64 = diskNumber == UInt16.max || centralDirectoryDisk == UInt16.max ||
                entriesOnDisk == UInt16.max || totalEntries == UInt16.max ||
                centralDirectorySize == UInt32.max || centralDirectoryOffset == UInt32.max
            if needsZIP64 {
                return try findZIP64EndOfCentralDirectory(source: source, classicRecordOffset: recordOffset)
            }
            guard diskNumber == 0, centralDirectoryDisk == 0, entriesOnDisk == totalEntries else {
                throw ZipReaderError.readFailed("Multi-disk ZIP packages are unsupported")
            }
            return EOCD(
                centralDirOffset: UInt64(centralDirectoryOffset),
                centralDirSize: UInt64(centralDirectorySize),
                entryCount: UInt64(totalEntries),
                recordOffset: recordOffset
            )
        }

        throw ZipReaderError.notZipArchive
    }

    private static func findZIP64EndOfCentralDirectory(source: any SVPPackageByteSource, classicRecordOffset: UInt64) throws -> EOCD {
        guard classicRecordOffset >= 20 else { throw ZipReaderError.readFailed("ZIP64 locator is missing") }
        let locatorOffset = classicRecordOffset - 20
        let locator = try source.read(offset: locatorOffset, length: 20)
        guard le32(locator, 0) == 0x07064b50, le32(locator, 4) == 0, le32(locator, 16) == 1 else {
            throw ZipReaderError.readFailed("ZIP64 locator is invalid")
        }
        let recordOffset = le64(locator, 8)
        let record = try source.read(offset: recordOffset, length: 56)
        guard le32(record, 0) == 0x06064b50, le64(record, 4) >= 44 else {
            throw ZipReaderError.readFailed("ZIP64 end record is invalid")
        }
        let recordEnd = try checkedAdd(recordOffset, try checkedAdd(12, le64(record, 4)))
        guard recordEnd == locatorOffset, le32(record, 16) == 0, le32(record, 20) == 0 else {
            throw ZipReaderError.readFailed("ZIP64 end record layout is invalid")
        }
        let entriesOnDisk = le64(record, 24)
        let totalEntries = le64(record, 32)
        guard entriesOnDisk == totalEntries else {
            throw ZipReaderError.readFailed("Multi-disk ZIP packages are unsupported")
        }
        return EOCD(
            centralDirOffset: le64(record, 48),
            centralDirSize: le64(record, 40),
            entryCount: totalEntries,
            recordOffset: recordOffset
        )
    }

    private static func resolveZIP64Values(
        extra: Data,
        compressedSize: UInt32,
        uncompressedSize: UInt32,
        localHeaderOffset: UInt32,
        diskStart: UInt16
    ) throws -> (compressedSize: UInt64, uncompressedSize: UInt64, localHeaderOffset: UInt64, diskStart: UInt32) {
        let needsZIP64 = compressedSize == UInt32.max || uncompressedSize == UInt32.max ||
            localHeaderOffset == UInt32.max || diskStart == UInt16.max
        guard needsZIP64 else {
            return (UInt64(compressedSize), UInt64(uncompressedSize), UInt64(localHeaderOffset), UInt32(diskStart))
        }

        var fieldOffset = 0
        while fieldOffset + 4 <= extra.count {
            let identifier = le16(extra, fieldOffset)
            let dataLength = Int(le16(extra, fieldOffset + 2))
            let dataOffset = fieldOffset + 4
            let fieldEnd = dataOffset + dataLength
            guard fieldEnd <= extra.count else { throw ZipReaderError.readFailed("ZIP extra field is truncated") }
            if identifier == 0x0001 {
                var valueOffset = dataOffset
                func next64() throws -> UInt64 {
                    guard valueOffset + 8 <= fieldEnd else { throw ZipReaderError.readFailed("ZIP64 extra field is truncated") }
                    defer { valueOffset += 8 }
                    return le64(extra, valueOffset)
                }
                let resolvedUncompressedSize = try uncompressedSize == UInt32.max ? next64() : UInt64(uncompressedSize)
                let resolvedCompressedSize = try compressedSize == UInt32.max ? next64() : UInt64(compressedSize)
                let resolvedLocalHeaderOffset = try localHeaderOffset == UInt32.max ? next64() : UInt64(localHeaderOffset)
                let resolvedDiskStart: UInt32
                if diskStart == UInt16.max {
                    guard valueOffset + 4 <= fieldEnd else { throw ZipReaderError.readFailed("ZIP64 extra field is truncated") }
                    resolvedDiskStart = le32(extra, valueOffset)
                } else {
                    resolvedDiskStart = UInt32(diskStart)
                }
                return (resolvedCompressedSize, resolvedUncompressedSize, resolvedLocalHeaderOffset, resolvedDiskStart)
            }
            fieldOffset = fieldEnd
        }
        throw ZipReaderError.readFailed("Required ZIP64 extra field is missing")
    }

    private static func checkedAdd(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw ZipReaderError.readFailed("ZIP offset arithmetic overflow") }
        return sum
    }

    private static func le16(_ data: Data, _ offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    private static func le32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    private static func le64(_ data: Data, _ offset: Int) -> UInt64 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
    }

    private func checkedAdd(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, sum <= fileLength else { throw ZipReaderError.readFailed("ZIP offset is outside the logical package source") }
        return sum
    }

    static func inflate(data: Data, expectedSize: UInt64) throws -> Data {
        var output = Data()
        if expectedSize > 0 && expectedSize < 512 * 1024 * 1024 {
            output.reserveCapacity(Int(expectedSize))
        }

        let stream = cZlib_inflate_init()
        guard stream != nil else {
            throw ZipReaderError.inflateFailed("inflate init failed")
        }
        defer { cZlib_inflate_end(stream) }

        let chunkSize = 65536
        var outputBuffer = [UInt8](repeating: 0, count: chunkSize)
        var inputOffset = 0
        let inputTotal = data.count
        var done = false

        while !done && inputOffset < inputTotal {
            let remaining = inputTotal - inputOffset
            let inputChunk = min(remaining, chunkSize)
            var consumed: Int = 0
            var produced: Int = 0

            let result = data.withUnsafeBytes { inputPtr in
                outputBuffer.withUnsafeMutableBufferPointer { outputPtr in
                    cZlib_inflate_process(
                        stream,
                        inputPtr.baseAddress?.advanced(by: inputOffset),
                        inputChunk,
                        outputPtr.baseAddress,
                        chunkSize,
                        &consumed,
                        &produced
                    )
                }
            }

            if result < 0 {
                throw ZipReaderError.inflateFailed("inflate process failed")
            }

            if produced > 0 {
                output.append(contentsOf: outputBuffer[0..<produced])
            }

            inputOffset += consumed

            if result == 1 {
                done = true
            }

            if consumed == 0 && produced == 0 {
                break
            }
        }

        return output
    }
}
