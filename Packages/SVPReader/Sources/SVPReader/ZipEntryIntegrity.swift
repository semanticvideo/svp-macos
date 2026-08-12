import CZlib
import Foundation

struct ZipEntryIntegrity {
    private let entryName: String
    private let expectedSize: UInt64
    private let expectedCRC32: UInt32
    private(set) var producedSize: UInt64 = 0
    private var crc32: UInt32 = 0

    init(entry: ZipCentralDirEntry) {
        entryName = entry.fileName
        expectedSize = entry.uncompressedSize
        expectedCRC32 = entry.crc32
    }

    mutating func consume(_ data: Data) throws {
        let (newSize, overflow) = producedSize.addingReportingOverflow(UInt64(data.count))
        guard !overflow, newSize <= expectedSize else {
            throw ZipReaderError.readFailed("ZIP entry produced more bytes than declared: \(entryName)")
        }

        if !data.isEmpty {
            crc32 = data.withUnsafeBytes { bytes in
                cZlib_crc32(crc32, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
            }
        }
        producedSize = newSize
    }

    func validate(streamEnded: Bool = true) throws {
        guard streamEnded else {
            throw ZipReaderError.inflateFailed("Deflate stream ended before completion: \(entryName)")
        }
        guard producedSize == expectedSize else {
            throw ZipReaderError.readFailed(
                "ZIP entry size mismatch for \(entryName): expected \(expectedSize), produced \(producedSize)"
            )
        }
        guard crc32 == expectedCRC32 else {
            throw ZipReaderError.readFailed("ZIP entry CRC32 mismatch: \(entryName)")
        }
    }
}
