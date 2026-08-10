import CZlib
import Foundation

struct ZipEntryExtractor {
    private let source: any SVPPackageByteSource
    private let localEntryLocator: ZipLocalEntryLocator

    init(
        source: any SVPPackageByteSource,
        localEntryLocator: ZipLocalEntryLocator
    ) {
        self.source = source
        self.localEntryLocator = localEntryLocator
    }

    func extractEntry(
        _ entry: ZipCentralDirEntry,
        to destinationURL: URL,
        bufferSize: Int
    ) throws {
        guard bufferSize > 0 else {
            throw ZipReaderError.readFailed("ZIP extraction buffer size must be greater than zero")
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-extraction-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try extractEntryData(entry: entry, to: temporaryURL, bufferSize: bufferSize)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func extractEntryData(
        entry: ZipCentralDirEntry,
        to destinationURL: URL,
        bufferSize: Int
    ) throws {
        let dataOffset = try localEntryLocator.dataOffset(for: entry)

        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ZipReaderError.readFailed("Cannot create destination: \(destinationURL.path)")
        }
        guard let outputHandle = try? FileHandle(forWritingTo: destinationURL) else {
            throw ZipReaderError.readFailed("Cannot open destination: \(destinationURL.path)")
        }
        defer { try? outputHandle.close() }

        var integrity = ZipEntryIntegrity(entry: entry)
        if entry.compressionMethod == 0 {
            try copyStoredEntry(
                offset: dataOffset,
                byteCount: entry.uncompressedSize,
                to: outputHandle,
                bufferSize: bufferSize,
                integrity: &integrity
            )
            try integrity.validate()
        } else if entry.compressionMethod == 8 {
            let streamEnded = try inflateEntry(
                offset: dataOffset,
                compressedByteCount: entry.compressedSize,
                to: outputHandle,
                bufferSize: bufferSize,
                integrity: &integrity
            )
            try integrity.validate(streamEnded: streamEnded)
        } else {
            throw ZipReaderError.readFailed(
                "Unsupported compression method: \(entry.compressionMethod)"
            )
        }
    }

    private func copyStoredEntry(
        offset: UInt64,
        byteCount: UInt64,
        to outputHandle: FileHandle,
        bufferSize: Int,
        integrity: inout ZipEntryIntegrity
    ) throws {
        var remaining = byteCount
        var position = offset
        while remaining > 0 {
            let bytesToRead = Int(min(UInt64(bufferSize), remaining))
            let chunk = try source.read(offset: position, length: bytesToRead)
            guard !chunk.isEmpty else {
                throw ZipReaderError.readFailed("ZIP entry ended before its declared size")
            }
            try integrity.consume(chunk)
            try outputHandle.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
            position = try localEntryLocator.checkedAdd(position, UInt64(chunk.count))
        }
    }

    private func inflateEntry(
        offset: UInt64,
        compressedByteCount: UInt64,
        to outputHandle: FileHandle,
        bufferSize: Int,
        integrity: inout ZipEntryIntegrity
    ) throws -> Bool {
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
        var streamEnded = false

        while remaining > 0, !streamEnded {
            let bytesToRead = Int(min(UInt64(inputChunkSize), remaining))
            let chunk = try source.read(offset: position, length: bytesToRead)
            guard !chunk.isEmpty else {
                throw ZipReaderError.inflateFailed(
                    "Compressed ZIP entry ended before its declared size"
                )
            }

            var inputOffset = 0
            while inputOffset < chunk.count, !streamEnded {
                var consumed = 0
                var produced = 0

                let result = chunk.withUnsafeBytes { inputPointer in
                    outputBuffer.withUnsafeMutableBufferPointer { outputPointer in
                        cZlib_inflate_process(
                            stream,
                            inputPointer.baseAddress?.advanced(by: inputOffset),
                            chunk.count - inputOffset,
                            outputPointer.baseAddress,
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
                    let output = Data(outputBuffer[0..<produced])
                    try integrity.consume(output)
                    try outputHandle.write(contentsOf: output)
                }

                inputOffset += consumed

                if result == 1 {
                    streamEnded = true
                    guard inputOffset == chunk.count, remaining == UInt64(chunk.count) else {
                        throw ZipReaderError.inflateFailed(
                            "Deflate stream contains trailing compressed data"
                        )
                    }
                }

                if consumed == 0 && produced == 0 {
                    throw ZipReaderError.inflateFailed("Deflate stream made no progress")
                }
            }

            remaining -= UInt64(chunk.count)
            position = try localEntryLocator.checkedAdd(position, UInt64(chunk.count))
        }

        return streamEnded
    }
}
