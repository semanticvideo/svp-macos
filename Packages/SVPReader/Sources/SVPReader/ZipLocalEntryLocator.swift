import Foundation

struct ZipLocalEntryLocator {
    private let source: any SVPPackageByteSource
    private let fileLength: UInt64

    init(source: any SVPPackageByteSource, fileLength: UInt64) {
        self.source = source
        self.fileLength = fileLength
    }

    func dataOffset(for entry: ZipCentralDirEntry) throws -> UInt64 {
        let localHeader = try readLocalHeader(for: entry)
        return try checkedAdd(entry.localHeaderOffset, localHeader.dataOffset)
    }

    func readLocalHeader(for entry: ZipCentralDirEntry) throws -> ZipLocalHeader {
        let localHeader = try readLocalHeader(offset: entry.localHeaderOffset)
        guard localHeader.compressionMethod == entry.compressionMethod else {
            throw ZipReaderError.readFailed(
                "ZIP local and central compression methods disagree: \(entry.fileName)"
            )
        }
        return localHeader
    }

    func checkedAdd(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, sum <= fileLength else {
            throw ZipReaderError.readFailed("ZIP offset is outside the logical package source")
        }
        return sum
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

        let compressionMethod = headerData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 8, as: UInt16.self)
        }
        let compressedSize = headerData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 18, as: UInt32.self)
        }
        let uncompressedSize = headerData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 22, as: UInt32.self)
        }
        let fileNameLength = headerData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 26, as: UInt16.self)
        }
        let extraFieldLength = headerData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 28, as: UInt16.self)
        }
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
}
