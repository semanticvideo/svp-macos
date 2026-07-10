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
        if local.uncompressedSize != 0 { return local.uncompressedSize }
        return central.uncompressedSize
    }

    private func resolveCompressedSize(local: ZipLocalHeader, central: ZipCentralDirEntry) -> UInt64 {
        if local.compressedSize != 0 { return local.compressedSize }
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
        let cdData = try source.read(offset: UInt64(eocd.centralDirOffset), length: Int(eocd.centralDirSize))

        var entries: [ZipCentralDirEntry] = []
        var offset = 0

        while offset + 46 <= cdData.count {
            let signature = cdData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            guard signature == 0x02014b50 else { break }

            cdData.withUnsafeBytes { ptr in
                let compressionMethod = ptr.loadUnaligned(fromByteOffset: offset + 10, as: UInt16.self)
                let crc32 = ptr.loadUnaligned(fromByteOffset: offset + 16, as: UInt32.self)
                let compressedSize = UInt64(ptr.loadUnaligned(fromByteOffset: offset + 20, as: UInt32.self))
                let uncompressedSize = UInt64(ptr.loadUnaligned(fromByteOffset: offset + 24, as: UInt32.self))
                let fileNameLength = Int(ptr.loadUnaligned(fromByteOffset: offset + 28, as: UInt16.self))
                let extraFieldLength = Int(ptr.loadUnaligned(fromByteOffset: offset + 30, as: UInt16.self))
                let fileCommentLength = Int(ptr.loadUnaligned(fromByteOffset: offset + 32, as: UInt16.self))
                let localHeaderOffset = UInt64(ptr.loadUnaligned(fromByteOffset: offset + 42, as: UInt32.self))

                let fileNameStart = offset + 46
                let fileNameEnd = fileNameStart + fileNameLength
                if fileNameEnd <= cdData.count {
                    let fileNameBytes = Array(cdData[fileNameStart..<fileNameEnd])
                    let fileName = String(bytes: fileNameBytes, encoding: .utf8) ?? ""

                    entries.append(ZipCentralDirEntry(
                        fileName: fileName,
                        compressionMethod: compressionMethod,
                        compressedSize: compressedSize,
                        uncompressedSize: uncompressedSize,
                        localHeaderOffset: localHeaderOffset,
                        crc32: crc32
                    ))
                }

                offset = fileNameEnd + extraFieldLength + fileCommentLength
            }
        }

        return entries
    }

    private struct EOCD {
        let centralDirOffset: UInt32
        let centralDirSize: UInt32
    }

    private static func findEndOfCentralDirectory(source: any SVPPackageByteSource, fileLength: UInt64) throws -> EOCD {
        let maxScan = min(UInt64(65557), fileLength)
        let scanStart = fileLength - maxScan
        let scanData = try source.read(offset: scanStart, length: Int(maxScan))

        guard scanData.count >= 22 else { throw ZipReaderError.notZipArchive }

        for i in stride(from: scanData.count - 22, through: 0, by: -1) {
            let sig = scanData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i, as: UInt32.self) }
            if sig == 0x06054b50 {
                let cdSize = scanData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i + 12, as: UInt32.self) }
                let cdOffset = scanData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i + 16, as: UInt32.self) }
                return EOCD(centralDirOffset: cdOffset, centralDirSize: cdSize)
            }
        }

        throw ZipReaderError.notZipArchive
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
