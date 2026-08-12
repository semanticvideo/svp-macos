import CBlake3
import Foundation

public enum EmbeddedSVPIIntegrityVerifier {
    public static func verify(source: any SVPPackageByteSource, expectedHash: Data) throws {
        guard try digest(source: source) == expectedHash else { throw EmbeddedSVPIError.payloadHashMismatch }
    }

    static func digest(source: any SVPPackageByteSource) throws -> Data {
        var hasher = blake3_hasher()
        blake3_hasher_init(&hasher)
        var offset: UInt64 = 0
        let chunkSize = 1_048_576
        while offset < source.length {
            let count = Int(min(UInt64(chunkSize), source.length - offset))
            let data = try source.read(offset: offset, length: count)
            data.withUnsafeBytes { blake3_hasher_update(&hasher, $0.baseAddress, data.count) }
            offset += UInt64(data.count)
        }
        var digest = Data(count: EmbeddedSVPITransportProfile.hashSize)
        let digestCount = digest.count
        digest.withUnsafeMutableBytes { blake3_hasher_finalize(&hasher, $0.baseAddress, digestCount) }
        return digest
    }
}
