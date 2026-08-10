import Foundation

enum ZipArchiveIndex {
    private struct EndOfCentralDirectory {
        let centralDirOffset: UInt64
        let centralDirSize: UInt64
        let entryCount: UInt64
        let recordOffset: UInt64
    }

    static func parse(
        source: any SVPPackageByteSource,
        fileLength: UInt64
    ) throws -> [ZipCentralDirEntry] {
        let endRecord = try findEndOfCentralDirectory(source: source, fileLength: fileLength)
        var entries: [ZipCentralDirEntry] = []
        let centralDirectoryEnd = try ZipBinaryDecoder.checkedAdd(
            endRecord.centralDirOffset,
            endRecord.centralDirSize
        )
        guard centralDirectoryEnd <= endRecord.recordOffset else {
            throw ZipReaderError.readFailed("ZIP central directory overlaps end records")
        }
        var offset = endRecord.centralDirOffset

        while offset < centralDirectoryEnd {
            guard centralDirectoryEnd - offset >= 46 else {
                throw ZipReaderError.readFailed("ZIP central directory record is truncated")
            }
            let header = try source.read(offset: offset, length: 46)
            guard ZipBinaryDecoder.le32(header, 0) == 0x02014b50 else {
                throw ZipReaderError.readFailed("Invalid ZIP central directory signature")
            }

            let compressionMethod = ZipBinaryDecoder.le16(header, 10)
            let crc32 = ZipBinaryDecoder.le32(header, 16)
            let compactCompressedSize = ZipBinaryDecoder.le32(header, 20)
            let compactUncompressedSize = ZipBinaryDecoder.le32(header, 24)
            let fileNameLength = UInt64(ZipBinaryDecoder.le16(header, 28))
            let extraFieldLength = UInt64(ZipBinaryDecoder.le16(header, 30))
            let fileCommentLength = UInt64(ZipBinaryDecoder.le16(header, 32))
            let compactDiskStart = ZipBinaryDecoder.le16(header, 34)
            let compactLocalHeaderOffset = ZipBinaryDecoder.le32(header, 42)
            let variableLength = try ZipBinaryDecoder.checkedAdd(
                try ZipBinaryDecoder.checkedAdd(fileNameLength, extraFieldLength),
                fileCommentLength
            )
            let recordLength = try ZipBinaryDecoder.checkedAdd(46, variableLength)
            let recordEnd = try ZipBinaryDecoder.checkedAdd(offset, recordLength)
            guard recordEnd <= centralDirectoryEnd else {
                throw ZipReaderError.readFailed("ZIP central directory record extends outside its declared range")
            }

            let fileNameOffset = try ZipBinaryDecoder.checkedAdd(offset, 46)
            let fileNameData = try source.read(offset: fileNameOffset, length: Int(fileNameLength))
            guard let fileName = String(data: fileNameData, encoding: .utf8), !fileName.isEmpty else {
                throw ZipReaderError.readFailed("ZIP entry name is empty or invalid UTF-8")
            }
            let extraOffset = try ZipBinaryDecoder.checkedAdd(fileNameOffset, fileNameLength)
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
            guard UInt64(entries.count) <= endRecord.entryCount else {
                throw ZipReaderError.readFailed("ZIP central directory contains more entries than declared")
            }
            offset = recordEnd
        }
        guard offset == centralDirectoryEnd, UInt64(entries.count) == endRecord.entryCount else {
            throw ZipReaderError.readFailed("ZIP central directory entry count does not match its end record")
        }
        return entries
    }

    private static func findEndOfCentralDirectory(
        source: any SVPPackageByteSource,
        fileLength: UInt64
    ) throws -> EndOfCentralDirectory {
        let maxScan = min(UInt64(65_557), fileLength)
        let scanStart = fileLength - maxScan
        let scanData = try source.read(offset: scanStart, length: Int(maxScan))

        guard scanData.count >= 22 else {
            throw ZipReaderError.notZipArchive
        }

        for index in stride(from: scanData.count - 22, through: 0, by: -1) {
            guard ZipBinaryDecoder.le32(scanData, index) == 0x06054b50 else { continue }
            let commentLength = UInt64(ZipBinaryDecoder.le16(scanData, index + 20))
            let recordOffset = try ZipBinaryDecoder.checkedAdd(scanStart, UInt64(index))
            guard try ZipBinaryDecoder.checkedAdd(
                recordOffset,
                try ZipBinaryDecoder.checkedAdd(22, commentLength)
            ) == fileLength else { continue }
            let diskNumber = ZipBinaryDecoder.le16(scanData, index + 4)
            let centralDirectoryDisk = ZipBinaryDecoder.le16(scanData, index + 6)
            let entriesOnDisk = ZipBinaryDecoder.le16(scanData, index + 8)
            let totalEntries = ZipBinaryDecoder.le16(scanData, index + 10)
            let centralDirectorySize = ZipBinaryDecoder.le32(scanData, index + 12)
            let centralDirectoryOffset = ZipBinaryDecoder.le32(scanData, index + 16)

            let needsZIP64 = diskNumber == UInt16.max || centralDirectoryDisk == UInt16.max
                || entriesOnDisk == UInt16.max || totalEntries == UInt16.max
                || centralDirectorySize == UInt32.max || centralDirectoryOffset == UInt32.max
            if needsZIP64 {
                return try findZIP64EndOfCentralDirectory(
                    source: source,
                    classicRecordOffset: recordOffset
                )
            }
            guard diskNumber == 0, centralDirectoryDisk == 0, entriesOnDisk == totalEntries else {
                throw ZipReaderError.readFailed("Multi-disk ZIP packages are unsupported")
            }
            return EndOfCentralDirectory(
                centralDirOffset: UInt64(centralDirectoryOffset),
                centralDirSize: UInt64(centralDirectorySize),
                entryCount: UInt64(totalEntries),
                recordOffset: recordOffset
            )
        }

        throw ZipReaderError.notZipArchive
    }

    private static func findZIP64EndOfCentralDirectory(
        source: any SVPPackageByteSource,
        classicRecordOffset: UInt64
    ) throws -> EndOfCentralDirectory {
        guard classicRecordOffset >= 20 else {
            throw ZipReaderError.readFailed("ZIP64 locator is missing")
        }
        let locatorOffset = classicRecordOffset - 20
        let locator = try source.read(offset: locatorOffset, length: 20)
        guard ZipBinaryDecoder.le32(locator, 0) == 0x07064b50,
              ZipBinaryDecoder.le32(locator, 4) == 0,
              ZipBinaryDecoder.le32(locator, 16) == 1 else {
            throw ZipReaderError.readFailed("ZIP64 locator is invalid")
        }
        let recordOffset = ZipBinaryDecoder.le64(locator, 8)
        let record = try source.read(offset: recordOffset, length: 56)
        guard ZipBinaryDecoder.le32(record, 0) == 0x06064b50,
              ZipBinaryDecoder.le64(record, 4) >= 44 else {
            throw ZipReaderError.readFailed("ZIP64 end record is invalid")
        }
        let recordEnd = try ZipBinaryDecoder.checkedAdd(
            recordOffset,
            try ZipBinaryDecoder.checkedAdd(12, ZipBinaryDecoder.le64(record, 4))
        )
        guard recordEnd == locatorOffset,
              ZipBinaryDecoder.le32(record, 16) == 0,
              ZipBinaryDecoder.le32(record, 20) == 0 else {
            throw ZipReaderError.readFailed("ZIP64 end record layout is invalid")
        }
        let entriesOnDisk = ZipBinaryDecoder.le64(record, 24)
        let totalEntries = ZipBinaryDecoder.le64(record, 32)
        guard entriesOnDisk == totalEntries else {
            throw ZipReaderError.readFailed("Multi-disk ZIP packages are unsupported")
        }
        return EndOfCentralDirectory(
            centralDirOffset: ZipBinaryDecoder.le64(record, 48),
            centralDirSize: ZipBinaryDecoder.le64(record, 40),
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
    ) throws -> (
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        localHeaderOffset: UInt64,
        diskStart: UInt32
    ) {
        let needsZIP64 = compressedSize == UInt32.max || uncompressedSize == UInt32.max
            || localHeaderOffset == UInt32.max || diskStart == UInt16.max
        guard needsZIP64 else {
            return (
                UInt64(compressedSize),
                UInt64(uncompressedSize),
                UInt64(localHeaderOffset),
                UInt32(diskStart)
            )
        }

        var fieldOffset = 0
        while fieldOffset + 4 <= extra.count {
            let identifier = ZipBinaryDecoder.le16(extra, fieldOffset)
            let dataLength = Int(ZipBinaryDecoder.le16(extra, fieldOffset + 2))
            let dataOffset = fieldOffset + 4
            let fieldEnd = dataOffset + dataLength
            guard fieldEnd <= extra.count else {
                throw ZipReaderError.readFailed("ZIP extra field is truncated")
            }
            if identifier == 0x0001 {
                var valueOffset = dataOffset
                func next64() throws -> UInt64 {
                    guard valueOffset + 8 <= fieldEnd else {
                        throw ZipReaderError.readFailed("ZIP64 extra field is truncated")
                    }
                    defer { valueOffset += 8 }
                    return ZipBinaryDecoder.le64(extra, valueOffset)
                }
                let resolvedUncompressedSize = try uncompressedSize == UInt32.max
                    ? next64()
                    : UInt64(uncompressedSize)
                let resolvedCompressedSize = try compressedSize == UInt32.max
                    ? next64()
                    : UInt64(compressedSize)
                let resolvedLocalHeaderOffset = try localHeaderOffset == UInt32.max
                    ? next64()
                    : UInt64(localHeaderOffset)
                let resolvedDiskStart: UInt32
                if diskStart == UInt16.max {
                    guard valueOffset + 4 <= fieldEnd else {
                        throw ZipReaderError.readFailed("ZIP64 extra field is truncated")
                    }
                    resolvedDiskStart = ZipBinaryDecoder.le32(extra, valueOffset)
                } else {
                    resolvedDiskStart = UInt32(diskStart)
                }
                return (
                    resolvedCompressedSize,
                    resolvedUncompressedSize,
                    resolvedLocalHeaderOffset,
                    resolvedDiskStart
                )
            }
            fieldOffset = fieldEnd
        }
        throw ZipReaderError.readFailed("Required ZIP64 extra field is missing")
    }
}
