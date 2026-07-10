import Foundation

public enum SemanticMediaStatus: Sendable {
    case embedded(package: SVPPackageDescriptor)
    case noEmbeddedSvpi
    case invalidEmbedding(EmbeddedSVPIError)
    case unsupportedContainer
}

public enum SemanticMediaResolver {
    public static func resolve(url: URL) -> SemanticMediaStatus {
        do {
            let fileSource = try FilePackageByteSource(url: url)
            guard let scan = try ISOBMFFScanner.scan(source: fileSource) else { return .unsupportedContainer }
            guard !scan.embeddingCandidates.isEmpty else { return .noEmbeddedSvpi }
            guard scan.embeddingCandidates.count == 1 else { return .invalidEmbedding(.duplicateEmbeddings) }
            let candidate = scan.embeddingCandidates[0]
            let envelope = try EmbeddedSVPIEnvelopeParser.parse(candidate: candidate, source: fileSource)
            let bounded = try BoundedPackageByteSource(source: fileSource, baseOffset: envelope.payloadOffset, length: envelope.payloadLength)
            try EmbeddedSVPIIntegrityVerifier.verify(source: bounded, expectedHash: envelope.expectedHash)
            let descriptor = SVPPackageDescriptor(source: bounded, mediaURL: url, containerFamily: scan.family, majorBrand: scan.majorBrand, compatibleBrands: scan.compatibleBrands, profileVersion: envelope.profileVersion, uuidBoxOffset: candidate.boxOffset, payloadOffset: envelope.payloadOffset, payloadSize: envelope.payloadLength, payloadHash: envelope.expectedHash, payloadHashMatches: true)
            let reader = try SVPReader(package: descriptor)
            try reader.validateSVP()
            return .embedded(package: descriptor)
        } catch let error as EmbeddedSVPIError {
            return .invalidEmbedding(error)
        } catch {
            return .invalidEmbedding(.invalidPackage(String(describing: error)))
        }
    }
}
