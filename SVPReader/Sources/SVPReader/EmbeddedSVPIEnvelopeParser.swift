import Foundation

public struct EmbeddedSVPIEnvelope: Sendable {
    public let profileVersion: UInt16
    public let payloadLength: UInt64
    public let expectedHash: Data
    public let payloadOffset: UInt64
}

public enum EmbeddedSVPIEnvelopeParser {
    public static func parse(candidate: ISOBMFFEmbeddingCandidate, source: any SVPPackageByteSource) throws -> EmbeddedSVPIEnvelope {
        guard candidate.contentSize >= UInt64(EmbeddedSVPITransportProfile.envelopeSize) else { throw EmbeddedSVPIError.truncatedUUIDBox(offset: candidate.boxOffset) }
        let envelope = try source.read(offset: candidate.contentOffset, length: Int(EmbeddedSVPITransportProfile.envelopeSize))
        guard envelope.prefix(8) == EmbeddedSVPITransportProfile.magic else { throw EmbeddedSVPIError.invalidEnvelope("Embedded SVPI envelope signature is invalid.") }
        let version = ISOBMFFScanner.be16(envelope, 8)
        guard version == EmbeddedSVPITransportProfile.version else { throw EmbeddedSVPIError.unsupportedVersion(version) }
        guard ISOBMFFScanner.be16(envelope, 10) == EmbeddedSVPITransportProfile.envelopeSize else { throw EmbeddedSVPIError.invalidEnvelope("Embedded SVPI envelope size is not 64 bytes.") }
        let flags = ISOBMFFScanner.be32(envelope, 12)
        guard flags == EmbeddedSVPITransportProfile.supportedFlags else { throw EmbeddedSVPIError.unsupportedFlags(flags) }
        guard envelope[EmbeddedSVPITransportProfile.reservedRange].allSatisfy({ $0 == 0 }) else { throw EmbeddedSVPIError.unsupportedFlags(flags) }
        let payloadLength = ISOBMFFScanner.be64(envelope, 16)
        let actualLength = candidate.contentSize - UInt64(EmbeddedSVPITransportProfile.envelopeSize)
        guard payloadLength == actualLength else { throw EmbeddedSVPIError.payloadLengthMismatch(declared: payloadLength, actual: actualLength) }
        let (payloadOffset, overflow) = candidate.contentOffset.addingReportingOverflow(UInt64(EmbeddedSVPITransportProfile.envelopeSize))
        guard !overflow else { throw EmbeddedSVPIError.payloadOutOfBounds }
        let (payloadEnd, endOverflow) = payloadOffset.addingReportingOverflow(payloadLength)
        guard !endOverflow, payloadEnd <= source.length else { throw EmbeddedSVPIError.payloadOutOfBounds }
        return EmbeddedSVPIEnvelope(profileVersion: version, payloadLength: payloadLength, expectedHash: Data(envelope[24..<56]), payloadOffset: payloadOffset)
    }
}
