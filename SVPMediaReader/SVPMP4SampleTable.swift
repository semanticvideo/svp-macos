import Foundation
import AVFoundation
import CoreMedia

struct SVPMP4Sample {
    let offset: UInt64
    let size: UInt32
    let dts: CMTime
    let pts: CMTime
    let duration: CMTime
    let isSync: Bool
}

struct SVPMP4TrackSamples {
    let mediaType: AVMediaType
    let timescale: Int32
    let samples: [SVPMP4Sample]
}

enum SVPMP4SampleTableError: Error {
    case invalidFile
    case missingSampleTable
}

final class SVPMP4SampleTableParser {
    private struct Box {
        let type: String
        let offset: Int
        let headerSize: Int
        let size: Int

        var payloadStart: Int { offset + headerSize }
        var payloadEnd: Int { offset + size }
    }

    private let data: Data

    init(url: URL) throws {
        self.data = try Self.readMovieBox(from: url)
    }

    func parseTracks() throws -> [SVPMP4TrackSamples] {
        try boxes(in: 0..<data.count)
            .filter { $0.type == "trak" }
            .compactMap { try parseTrack($0) }
    }

    private static func readMovieBox(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let fileLength = try handle.seekToEnd()
        var offset: UInt64 = 0

        while offset + 8 <= fileLength {
            let box = try readTopLevelBoxHeader(from: handle, at: offset, fileLimit: fileLength)

            if box.type == "moov" {
                let payloadSize = box.size - box.headerSize
                guard payloadSize <= UInt64(Int.max) else {
                    throw SVPMP4SampleTableError.invalidFile
                }
                try handle.seek(toOffset: offset + box.headerSize)
                guard let payload = try handle.read(upToCount: Int(payloadSize)),
                      payload.count == Int(payloadSize)
                else {
                    throw SVPMP4SampleTableError.invalidFile
                }
                return payload
            }

            offset += box.size
        }

        throw SVPMP4SampleTableError.invalidFile
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

    private func parseTrack(_ trak: Box) throws -> SVPMP4TrackSamples? {
        guard let mdia = child("mdia", in: trak),
              let hdlr = child("hdlr", in: mdia),
              let mdhd = child("mdhd", in: mdia),
              let minf = child("minf", in: mdia),
              let stbl = child("stbl", in: minf)
        else {
            return nil
        }

        let handler = string(at: hdlr.payloadStart + 8, count: 4)
        let mediaType: AVMediaType
        if handler == "vide" {
            mediaType = .video
        } else if handler == "soun" {
            mediaType = .audio
        } else {
            return nil
        }

        let timescale = try parseTimescale(mdhd)
        let durations = try parseSTTS(requiredChild("stts", in: stbl))
        let compositionOffsets = parseCTTS(child("ctts", in: stbl))
        let syncSamples = parseSTSS(child("stss", in: stbl))
        let sampleSizes = try parseSTSZ(requiredChild("stsz", in: stbl))
        let chunkOffsets = try parseChunkOffsets(stbl)
        let stsc = try parseSTSC(requiredChild("stsc", in: stbl))
        let sampleOffsets = buildSampleOffsets(sampleSizes: sampleSizes, chunkOffsets: chunkOffsets, stsc: stsc)

        guard sampleOffsets.count == sampleSizes.count else {
            throw SVPMP4SampleTableError.missingSampleTable
        }

        var result: [SVPMP4Sample] = []
        result.reserveCapacity(sampleSizes.count)

        var dtsValue: Int64 = 0
        for index in sampleSizes.indices {
            let durationValue = Int64(durations[index])
            let ctsOffset = Int64(index < compositionOffsets.count ? compositionOffsets[index] : 0)
            let sampleNumber = index + 1
            let isSync = syncSamples?.contains(UInt32(sampleNumber)) ?? true
            let dts = CMTime(value: dtsValue, timescale: timescale)
            let pts = CMTime(value: dtsValue + ctsOffset, timescale: timescale)
            let duration = CMTime(value: durationValue, timescale: timescale)
            result.append(SVPMP4Sample(
                offset: sampleOffsets[index],
                size: sampleSizes[index],
                dts: dts,
                pts: pts,
                duration: duration,
                isSync: isSync
            ))
            dtsValue += durationValue
        }

        return SVPMP4TrackSamples(mediaType: mediaType, timescale: timescale, samples: result)
    }

    private func child(_ type: String, in parent: Box) -> Box? {
        boxes(in: parent.payloadStart..<parent.payloadEnd).first { $0.type == type }
    }

    private func requiredChild(_ type: String, in parent: Box) throws -> Box {
        guard let box = child(type, in: parent) else {
            throw SVPMP4SampleTableError.missingSampleTable
        }
        return box
    }

    private func boxes(in range: Range<Int>) -> [Box] {
        var boxes: [Box] = []
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            let smallSize = u32(offset)
            let type = string(at: offset + 4, count: 4)
            let headerSize: Int
            let size: Int
            if smallSize == 1 {
                guard offset + 16 <= range.upperBound else { break }
                headerSize = 16
                size = Int(u64(offset + 8))
            } else if smallSize == 0 {
                headerSize = 8
                size = range.upperBound - offset
            } else {
                headerSize = 8
                size = Int(smallSize)
            }
            guard size >= headerSize, offset + size <= range.upperBound else { break }
            boxes.append(Box(type: type, offset: offset, headerSize: headerSize, size: size))
            offset += size
        }
        return boxes
    }

    private func parseTimescale(_ mdhd: Box) throws -> Int32 {
        let version = u8(mdhd.payloadStart)
        if version == 1 {
            return Int32(bitPattern: u32(mdhd.payloadStart + 20))
        }
        return Int32(bitPattern: u32(mdhd.payloadStart + 12))
    }

    private func parseSTTS(_ stts: Box) throws -> [UInt32] {
        let entryCount = Int(u32(stts.payloadStart + 4))
        var cursor = stts.payloadStart + 8
        var durations: [UInt32] = []
        for _ in 0..<entryCount {
            let count = Int(u32(cursor))
            let delta = u32(cursor + 4)
            durations.append(contentsOf: repeatElement(delta, count: count))
            cursor += 8
        }
        return durations
    }

    private func parseCTTS(_ ctts: Box?) -> [Int32] {
        guard let ctts else { return [] }
        let version = u8(ctts.payloadStart)
        let entryCount = Int(u32(ctts.payloadStart + 4))
        var cursor = ctts.payloadStart + 8
        var offsets: [Int32] = []
        for _ in 0..<entryCount {
            let count = Int(u32(cursor))
            let raw = u32(cursor + 4)
            let value = version == 0 ? Int32(bitPattern: raw) : Int32(bitPattern: raw)
            offsets.append(contentsOf: repeatElement(value, count: count))
            cursor += 8
        }
        return offsets
    }

    private func parseSTSS(_ stss: Box?) -> Set<UInt32>? {
        guard let stss else { return nil }
        let entryCount = Int(u32(stss.payloadStart + 4))
        var cursor = stss.payloadStart + 8
        var sync = Set<UInt32>()
        for _ in 0..<entryCount {
            sync.insert(u32(cursor))
            cursor += 4
        }
        return sync
    }

    private func parseSTSZ(_ stsz: Box) throws -> [UInt32] {
        let sampleSize = u32(stsz.payloadStart + 4)
        let sampleCount = Int(u32(stsz.payloadStart + 8))
        if sampleSize != 0 {
            return Array(repeating: sampleSize, count: sampleCount)
        }
        var cursor = stsz.payloadStart + 12
        var sizes: [UInt32] = []
        sizes.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            sizes.append(u32(cursor))
            cursor += 4
        }
        return sizes
    }

    private func parseChunkOffsets(_ stbl: Box) throws -> [UInt64] {
        if let co64 = child("co64", in: stbl) {
            let count = Int(u32(co64.payloadStart + 4))
            var cursor = co64.payloadStart + 8
            var offsets: [UInt64] = []
            offsets.reserveCapacity(count)
            for _ in 0..<count {
                offsets.append(u64(cursor))
                cursor += 8
            }
            return offsets
        }

        let stco = try requiredChild("stco", in: stbl)
        let count = Int(u32(stco.payloadStart + 4))
        var cursor = stco.payloadStart + 8
        var offsets: [UInt64] = []
        offsets.reserveCapacity(count)
        for _ in 0..<count {
            offsets.append(UInt64(u32(cursor)))
            cursor += 4
        }
        return offsets
    }

    private struct STSCEntry {
        let firstChunk: Int
        let samplesPerChunk: Int
    }

    private func parseSTSC(_ stsc: Box) throws -> [STSCEntry] {
        let count = Int(u32(stsc.payloadStart + 4))
        var cursor = stsc.payloadStart + 8
        var entries: [STSCEntry] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            entries.append(STSCEntry(firstChunk: Int(u32(cursor)), samplesPerChunk: Int(u32(cursor + 4))))
            cursor += 12
        }
        return entries
    }

    private func buildSampleOffsets(sampleSizes: [UInt32], chunkOffsets: [UInt64], stsc: [STSCEntry]) -> [UInt64] {
        var offsets: [UInt64] = []
        offsets.reserveCapacity(sampleSizes.count)
        var sampleIndex = 0

        for chunkIndex in 1...chunkOffsets.count {
            let stscIndex = stsc.lastIndex { $0.firstChunk <= chunkIndex } ?? 0
            let samplesPerChunk = stsc[stscIndex].samplesPerChunk
            var sampleOffset = chunkOffsets[chunkIndex - 1]
            for _ in 0..<samplesPerChunk where sampleIndex < sampleSizes.count {
                offsets.append(sampleOffset)
                sampleOffset += UInt64(sampleSizes[sampleIndex])
                sampleIndex += 1
            }
        }

        return offsets
    }

    private func u8(_ offset: Int) -> UInt8 {
        data[offset]
    }

    private func u32(_ offset: Int) -> UInt32 {
        data.withUnsafeBytes { ptr in
            UInt32(bigEndian: ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    private func u64(_ offset: Int) -> UInt64 {
        data.withUnsafeBytes { ptr in
            UInt64(bigEndian: ptr.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
        }
    }

    private func string(at offset: Int, count: Int) -> String {
        String(data: data.subdata(in: offset..<(offset + count)), encoding: .ascii) ?? ""
    }
}
