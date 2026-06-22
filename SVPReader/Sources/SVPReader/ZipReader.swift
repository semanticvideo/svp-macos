import Foundation
import CZlib

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
    private let fileHandle: FileHandle
    private let fileLength: UInt64
    private let centralDirEntries: [ZipCentralDirEntry]
    private let entryMap: [String: ZipCentralDirEntry]

    init(url: URL) throws {
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            throw ZipReaderError.fileOpenFailed("Cannot open file: \(url.path)")
        }
        self.fileHandle = fh
        let length = (try? fh.seekToEnd()) ?? 0
        self.fileLength = length

        let entries = try Self.parseCentralDirectory(fh: fh, fileLength: length)
        self.centralDirEntries = entries
        self.entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.fileName, $0) })
    }

    deinit {
        try? fileHandle.close()
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

    private func readBytes(count: Int) throws -> Data {
        guard let data = try fileHandle.read(upToCount: count) else {
            throw ZipReaderError.readFailed("read returned nil")
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
