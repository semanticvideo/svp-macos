import Foundation

enum SVPMP4InitializationSegmentWriter {
    static func write(from mediaFileURL: URL, mediaBaseOffset: UInt64 = 0, mediaSize: UInt64? = nil, to destinationURL: URL) throws {
        let inputHandle = try FileHandle(forReadingFrom: mediaFileURL)
        defer {
            try? inputHandle.close()
        }

        try? FileManager.default.removeItem(at: destinationURL)
        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw SVPMP4SampleTableError.invalidFile
        }
        var writeSucceeded = false
        defer {
            if !writeSucceeded {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }
        let outputHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? outputHandle.close()
        }

        let fileLength = try inputHandle.seekToEnd()
        let availableMediaSize = mediaSize ?? (fileLength - mediaBaseOffset)
        var offset: UInt64 = 0
        var wroteMovieBox = false

        while offset + 8 <= availableMediaSize {
            let box = try readTopLevelBoxHeader(from: inputHandle, at: mediaBaseOffset + offset, fileLimit: mediaBaseOffset + availableMediaSize)
            if box.type == "ftyp" || box.type == "moov" {
                try copyBytes(from: inputHandle, offset: mediaBaseOffset + offset, length: box.size, to: outputHandle)
                if box.type == "moov" {
                    wroteMovieBox = true
                    break
                }
            }
            offset += box.size
        }

        if !wroteMovieBox {
            throw SVPMP4SampleTableError.invalidFile
        }
        writeSucceeded = true
    }

    private struct TopLevelBoxHeader {
        let type: String
        let headerSize: UInt64
        let size: UInt64
    }

    private static func readTopLevelBoxHeader(from handle: FileHandle, at offset: UInt64, fileLimit: UInt64) throws -> TopLevelBoxHeader {
        try handle.seek(toOffset: offset)
        guard let header = try handle.read(upToCount: 16), header.count >= 8 else {
            throw SVPMP4SampleTableError.invalidFile
        }

        let smallSize = header.withUnsafeBytes {
            UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
        }
        let type = String(data: header.subdata(in: 4..<8), encoding: .ascii) ?? ""

        let headerSize: UInt64
        let boxSize: UInt64
        if smallSize == 1 {
            guard header.count >= 16 else {
                throw SVPMP4SampleTableError.invalidFile
            }
            headerSize = 16
            boxSize = header.withUnsafeBytes {
                UInt64(bigEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
            }
        } else if smallSize == 0 {
            headerSize = 8
            boxSize = fileLimit - offset
        } else {
            headerSize = 8
            boxSize = UInt64(smallSize)
        }

        guard boxSize >= headerSize, offset + boxSize <= fileLimit else {
            throw SVPMP4SampleTableError.invalidFile
        }

        return TopLevelBoxHeader(type: type, headerSize: headerSize, size: boxSize)
    }

    private static func copyBytes(from inputHandle: FileHandle, offset: UInt64, length: UInt64, to outputHandle: FileHandle) throws {
        try inputHandle.seek(toOffset: offset)
        var remaining = length
        while remaining > 0 {
            let readLength = Int(min(remaining, UInt64(1_048_576)))
            guard let chunk = try inputHandle.read(upToCount: readLength), !chunk.isEmpty else {
                throw SVPMP4SampleTableError.invalidFile
            }
            outputHandle.write(chunk)
            remaining -= UInt64(chunk.count)
        }
    }
}
