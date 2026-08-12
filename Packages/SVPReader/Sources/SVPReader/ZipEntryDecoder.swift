import CZlib
import Foundation

struct ZipEntryDecoder {
    private let source: any SVPPackageByteSource
    private let localEntryLocator: ZipLocalEntryLocator

    init(
        source: any SVPPackageByteSource,
        localEntryLocator: ZipLocalEntryLocator
    ) {
        self.source = source
        self.localEntryLocator = localEntryLocator
    }

    func readEntryData(entry: ZipCentralDirEntry) throws -> Data {
        let dataOffset = try localEntryLocator.dataOffset(for: entry)

        if entry.compressionMethod == 0 {
            let size = entry.uncompressedSize
            guard size <= UInt64(Int.max) else {
                throw ZipReaderError.readFailed("Entry is too large")
            }
            let data = try source.read(offset: dataOffset, length: Int(size))
            var integrity = ZipEntryIntegrity(entry: entry)
            try integrity.consume(data)
            try integrity.validate()
            return data
        } else if entry.compressionMethod == 8 {
            let compressedSize = entry.compressedSize
            guard compressedSize <= UInt64(Int.max) else {
                throw ZipReaderError.readFailed("Compressed entry is too large")
            }
            let compressedData = try source.read(offset: dataOffset, length: Int(compressedSize))
            return try Self.inflate(data: compressedData, entry: entry)
        } else {
            throw ZipReaderError.readFailed(
                "Unsupported compression method: \(entry.compressionMethod)"
            )
        }
    }

    static func inflate(data: Data, entry: ZipCentralDirEntry) throws -> Data {
        var output = Data()
        if entry.uncompressedSize > 0 && entry.uncompressedSize < 512 * 1024 * 1024 {
            output.reserveCapacity(Int(entry.uncompressedSize))
        }

        let stream = cZlib_inflate_init()
        guard stream != nil else {
            throw ZipReaderError.inflateFailed("inflate init failed")
        }
        defer { cZlib_inflate_end(stream) }

        let chunkSize = 65_536
        var outputBuffer = [UInt8](repeating: 0, count: chunkSize)
        var inputOffset = 0
        let inputTotal = data.count
        var done = false
        var integrity = ZipEntryIntegrity(entry: entry)

        while !done && inputOffset < inputTotal {
            let remaining = inputTotal - inputOffset
            let inputChunk = min(remaining, chunkSize)
            var consumed = 0
            var produced = 0

            let result = data.withUnsafeBytes { inputPointer in
                outputBuffer.withUnsafeMutableBufferPointer { outputPointer in
                    cZlib_inflate_process(
                        stream,
                        inputPointer.baseAddress?.advanced(by: inputOffset),
                        inputChunk,
                        outputPointer.baseAddress,
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
                let chunk = Data(outputBuffer[0..<produced])
                try integrity.consume(chunk)
                output.append(chunk)
            }

            inputOffset += consumed

            if result == 1 {
                done = true
            }

            if consumed == 0 && produced == 0 {
                throw ZipReaderError.inflateFailed("Deflate stream made no progress")
            }
        }

        guard inputOffset == inputTotal else {
            throw ZipReaderError.inflateFailed("Deflate stream contains trailing compressed data")
        }
        try integrity.validate(streamEnded: done)
        return output
    }
}
