import Foundation
import CZlib

public enum SVPError: Error, CustomStringConvertible, Sendable {
    case notSVPFile(String)
    case invalidZip(String)
    case manifestReadFailed(String)
    case manifestParseFailed(String)
    case noMediaFound(String)
    case unsupportedCodec(String)
    case extractionFailed(String)
    case sandboxAccessDenied(String)
    case ioError(String)

    public var description: String {
        switch self {
        case .notSVPFile(let msg): return "Not an SVP file: \(msg)"
        case .invalidZip(let msg): return "Invalid ZIP archive: \(msg)"
        case .manifestReadFailed(let msg): return "Manifest read failed: \(msg)"
        case .manifestParseFailed(let msg): return "Manifest parse failed: \(msg)"
        case .noMediaFound(let msg): return "No media found: \(msg)"
        case .unsupportedCodec(let msg): return "Unsupported codec: \(msg)"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .sandboxAccessDenied(let msg): return "Sandbox access denied: \(msg)"
        case .ioError(let msg): return "I/O error: \(msg)"
        }
    }
}

public struct SVPMediaInfo: Sendable {
    public let mediaPath: String
    public let mediaFileName: String
    public let fileExtension: String
    public let uncompressedSize: UInt64
    public let compressionMethod: UInt16
    public let localHeaderOffset: UInt64

    public var isCompressed: Bool {
        compressionMethod != 0
    }

    public var likelyPlayableByAVFoundation: Bool {
        let ext = fileExtension.lowercased()
        return ["mov", "mp4", "m4v", "avi"].contains(ext)
    }
}

public struct SVPManifestInfo: Sendable {
    public let svpVersion: String
    public let packageID: String
    public let createdUTC: String
    public let primaryMediaID: String
    public let timebaseUnit: String
    public let timebaseOrigin: String
}

public struct SVPReadResult: Sendable {
    public let manifest: SVPManifestInfo?
    public let mediaInfo: SVPMediaInfo
    public let mediaURL: URL
    public let isMaterialized: Bool
    public let tempDir: URL?
}
