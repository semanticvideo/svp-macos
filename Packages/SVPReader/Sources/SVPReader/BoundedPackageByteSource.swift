import Foundation

public struct BoundedPackageByteSource: SVPPackageByteSource, Sendable {
    public let length: UInt64
    public let baseOffset: UInt64
    private let source: any SVPPackageByteSource

    public init(source: any SVPPackageByteSource, baseOffset: UInt64, length: UInt64) throws {
        let (end, overflow) = baseOffset.addingReportingOverflow(length)
        guard !overflow, end <= source.length else { throw SVPPackageByteSourceError.outOfRange }
        self.source = source
        self.baseOffset = baseOffset
        self.length = length
    }

    public func read(offset: UInt64, length requestedLength: Int) throws -> Data {
        guard requestedLength >= 0 else { throw SVPPackageByteSourceError.invalidLength }
        let (logicalEnd, logicalOverflow) = offset.addingReportingOverflow(UInt64(requestedLength))
        guard !logicalOverflow, logicalEnd <= length else { throw SVPPackageByteSourceError.outOfRange }
        let (physicalOffset, physicalOverflow) = baseOffset.addingReportingOverflow(offset)
        guard !physicalOverflow else { throw SVPPackageByteSourceError.offsetOverflow }
        return try source.read(offset: physicalOffset, length: requestedLength)
    }
}
