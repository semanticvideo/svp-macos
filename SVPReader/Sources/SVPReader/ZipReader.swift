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

    private let fileHandle: FileHandle
    private let rangeFileHandle: FileHandle
    private let rangeInfoLock = NSLock()
    private var storedEntryRangeInfoCache: [String: StoredEntryRangeInfo] = [:]
    private let fileLength: UInt64
    private let centralDirEntries: [ZipCentralDirEntry]
    private let entryMap: [String: ZipCentralDirEntry]

    init(url: URL) throws {
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            throw ZipReaderError.fileOpenFailed("Cannot open file: \(url.path)")
        }
        guard let rangeFH = try? FileHandle(forReadingFrom: url) else {
            try? fh.close()
            throw ZipReaderError.fileOpenFailed("Cannot open file for range reads: \(url.path)")
        }
        self.fileHandle = fh
        self.rangeFileHandle = rangeFH
        let length = (try? fh.seekToEnd()) ?? 0
        self.fileLength = length

        let entries = try Self.parseCentralDirectory(fh: fh, fileLength: length)
        self.centralDirEntries = entries
        self.entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.fileName, $0) })
    }

    deinit {
        try? fileHandle.close()
        try? rangeFileHandle.close()
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
        return entry.localHeaderOffset + UInt64(localHeader.dataOffset)
    }

    func readStoredEntryRange(_ name: String, offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        let rangeInfo = try storedEntryRangeInfo(name)
        let entrySize = rangeInfo.size
        guard offset < entrySize else { return Data() }

        let bytesToRead = Int(min(UInt64(length), entrySize - offset))
        let dataOffset = rangeInfo.dataOffset + offset

        return try preadData(offset: dataOffset, length: bytesToRead)
    }

    private func readEntryData(entry: ZipCentralDirEntry) throws -> Data {
        let localHeader = try readLocalHeader(offset: entry.localHeaderOffset)

        let dataOffset = entry.localHeaderOffset + UInt64(localHeader.dataOffset)
        try fileHandle.seek(toOffset: dataOffset)

        if entry.compressionMethod == 0 {
            let size = resolveSize(local: localHeader, central: entry)
            let data = try readBytes(count: Int(size))
            return data
        } else if entry.compressionMethod == 8 {
            let compressedSize = resolveCompressedSize(local: localHeader, central: entry)
            let compressedData = try readBytes(count: Int(compressedSize))
            return try Self.inflate(data: compressedData, expectedSize: entry.uncompressedSize)
        } else {
            throw ZipReaderError.readFailed("Unsupported compression method: \(entry.compressionMethod)")
        }
    }

    private func extractEntryData(entry: ZipCentralDirEntry, to destinationURL: URL, bufferSize: Int) throws {
        let localHeader = try readLocalHeader(offset: entry.localHeaderOffset)
        let dataOffset = entry.localHeaderOffset + UInt64(localHeader.dataOffset)

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

        try fileHandle.seek(toOffset: dataOffset)

        if entry.compressionMethod == 0 {
            let size = resolveSize(local: localHeader, central: entry)
            try copyStoredEntry(byteCount: size, to: outputHandle, bufferSize: bufferSize)
        } else if entry.compressionMethod == 8 {
            let compressedSize = resolveCompressedSize(local: localHeader, central: entry)
            try inflateEntry(compressedByteCount: compressedSize, to: outputHandle, bufferSize: bufferSize)
        } else {
            throw ZipReaderError.readFailed("Unsupported compression method: \(entry.compressionMethod)")
        }
    }

    private func copyStoredEntry(byteCount: UInt64, to outputHandle: FileHandle, bufferSize: Int) throws {
        var remaining = byteCount
        while remaining > 0 {
            let toRead = Int(min(UInt64(bufferSize), remaining))
            guard let chunk = try fileHandle.read(upToCount: toRead), !chunk.isEmpty else {
                throw ZipReaderError.readFailed("Unexpected EOF while extracting stored entry")
            }
            outputHandle.write(chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    private func inflateEntry(compressedByteCount: UInt64, to outputHandle: FileHandle, bufferSize: Int) throws {
        let stream = cZlib_inflate_init()
        guard stream != nil else {
            throw ZipReaderError.inflateFailed("inflate init failed")
        }
        defer { cZlib_inflate_end(stream) }

        let inputChunkSize = max(1, bufferSize)
        let outputChunkSize = 65_536
        var remaining = compressedByteCount
        var outputBuffer = [UInt8](repeating: 0, count: outputChunkSize)

        while remaining > 0 {
            let toRead = Int(min(UInt64(inputChunkSize), remaining))
            guard let chunk = try fileHandle.read(upToCount: toRead), !chunk.isEmpty else {
                throw ZipReaderError.readFailed("Unexpected EOF while extracting deflated entry")
            }

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
        }
    }

    private func readBytes(count: Int) throws -> Data {
        guard let data = try fileHandle.read(upToCount: count) else {
            throw ZipReaderError.readFailed("read returned nil")
        }
        return data
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
            dataOffset: entry.localHeaderOffset + UInt64(localHeader.dataOffset),
            size: resolveSize(local: localHeader, central: entry)
        )

        storedEntryRangeInfoCache[name] = rangeInfo

        return rangeInfo
    }

    private func preadData(offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        guard offset <= UInt64(Int64.max) else {
            throw ZipReaderError.readFailed("Range offset exceeds supported file offset")
        }

        var data = Data(count: length)
        var totalRead = 0

        while totalRead < length {
            let readCount = data.withUnsafeMutableBytes { buffer in
                pread(
                    rangeFileHandle.fileDescriptor,
                    buffer.baseAddress!.advanced(by: totalRead),
                    length - totalRead,
                    off_t(offset + UInt64(totalRead))
                )
            }

            if readCount > 0 {
                totalRead += readCount
            } else if readCount == 0 {
                break
            } else if errno != EINTR {
                throw ZipReaderError.readFailed("pread failed: \(String(cString: strerror(errno)))")
            }
        }

        if totalRead < length {
            data.removeSubrange(totalRead..<length)
        }

        return data
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
        try fileHandle.seek(toOffset: offset)
        guard let headerData = try fileHandle.read(upToCount: 30) else {
            throw ZipReaderError.readFailed("read returned nil for local header")
        }
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

        let dataOffset = UInt64(30 + fileNameLength + extraFieldLength)

        return ZipLocalHeader(
            compressionMethod: compressionMethod,
            compressedSize: UInt64(compressedSize),
            uncompressedSize: UInt64(uncompressedSize),
            fileNameLength: fileNameLength,
            extraFieldLength: extraFieldLength,
            dataOffset: dataOffset
        )
    }

    private static func parseCentralDirectory(fh: FileHandle, fileLength: UInt64) throws -> [ZipCentralDirEntry] {
        let eocd = try findEndOfCentralDirectory(fh: fh, fileLength: fileLength)

        try fh.seek(toOffset: UInt64(eocd.centralDirOffset))
        guard let cdData = try fh.read(upToCount: Int(eocd.centralDirSize)) else {
            throw ZipReaderError.readFailed("read returned nil for central directory")
        }

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

    private static func findEndOfCentralDirectory(fh: FileHandle, fileLength: UInt64) throws -> EOCD {
        let maxScan = min(UInt64(65557), fileLength)
        let scanStart = fileLength - maxScan
        try fh.seek(toOffset: scanStart)
        guard let scanData = try fh.read(upToCount: Int(maxScan)) else {
            throw ZipReaderError.readFailed("read returned nil for EOCD scan")
        }

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
