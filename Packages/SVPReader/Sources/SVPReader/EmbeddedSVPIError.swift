import Foundation

public enum EmbeddedSVPIError: Error, Equatable, Sendable, CustomStringConvertible {
    case unreadable(String)
    case malformedContainer(String)
    case truncatedBoxHeader(offset: UInt64)
    case invalidBoxSize(offset: UInt64)
    case arithmeticOverflow(offset: UInt64)
    case zeroSizedTopLevelBox(offset: UInt64)
    case truncatedUUIDBox(offset: UInt64)
    case invalidEnvelope(String)
    case unsupportedVersion(UInt16)
    case unsupportedFlags(UInt32)
    case payloadLengthMismatch(declared: UInt64, actual: UInt64)
    case payloadOutOfBounds
    case payloadHashMismatch
    case duplicateEmbeddings
    case invalidPackage(String)

    public var description: String {
        switch self {
        case .unreadable(let message), .malformedContainer(let message), .invalidEnvelope(let message), .invalidPackage(let message): return message
        case .truncatedBoxHeader(let offset): return "Truncated ISO BMFF box header at byte \(offset)."
        case .invalidBoxSize(let offset): return "Invalid ISO BMFF box size at byte \(offset)."
        case .arithmeticOverflow(let offset): return "ISO BMFF offset overflow at byte \(offset)."
        case .zeroSizedTopLevelBox(let offset): return "Unsupported zero-sized top-level box at byte \(offset)."
        case .truncatedUUIDBox(let offset): return "Truncated Embedded SVPI UUID box at byte \(offset)."
        case .unsupportedVersion(let version): return "Unsupported Embedded SVPI profile version \(version)."
        case .unsupportedFlags(let flags): return "Unsupported Embedded SVPI flags \(flags)."
        case .payloadLengthMismatch(let declared, let actual): return "Embedded SVPI payload length mismatch (declared \(declared), actual \(actual))."
        case .payloadOutOfBounds: return "Embedded SVPI payload extends outside the media file."
        case .payloadHashMismatch: return "Embedded SVPI payload failed BLAKE3 integrity verification."
        case .duplicateEmbeddings: return "The media contains more than one Embedded SVPI payload."
        }
    }
}
