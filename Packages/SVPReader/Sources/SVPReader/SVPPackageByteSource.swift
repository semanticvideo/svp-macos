import Foundation

public protocol SVPPackageByteSource: Sendable {
    var length: UInt64 { get }
    func read(offset: UInt64, length: Int) throws -> Data
}

public enum SVPPackageByteSourceError: Error, Equatable, Sendable {
    case invalidLength
    case offsetOverflow
    case outOfRange
    case shortRead(expected: Int, actual: Int)
    case openFailed(String)
    case readFailed(Int32)
}
