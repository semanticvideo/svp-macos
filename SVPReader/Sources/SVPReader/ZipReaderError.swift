enum ZipReaderError: Error {
    case fileOpenFailed(String)
    case notZipArchive
    case readFailed(String)
    case inflateFailed(String)
    case entryNotFound(String)
}
