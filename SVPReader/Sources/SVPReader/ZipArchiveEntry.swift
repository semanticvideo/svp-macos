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
