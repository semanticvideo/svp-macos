import Foundation

public struct SVPPackageDescriptor: Sendable {
    public let source: any SVPPackageByteSource
    public let mediaURL: URL
    public let containerFamily: ISOBaseMediaFamily?
    public let majorBrand: String?
    public let compatibleBrands: [String]
    public let profileVersion: UInt16?
    public let uuidBoxOffset: UInt64?
    public let payloadOffset: UInt64
    public let payloadSize: UInt64
    public let payloadHash: Data?
    public let payloadHashMatches: Bool

    public static func standalone(url: URL) throws -> Self {
        let source = try FilePackageByteSource(url: url)
        return Self(source: source, mediaURL: url, containerFamily: nil, majorBrand: nil, compatibleBrands: [], profileVersion: nil, uuidBoxOffset: nil, payloadOffset: 0, payloadSize: source.length, payloadHash: nil, payloadHashMatches: false)
    }
}
