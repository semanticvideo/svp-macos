import Darwin
import Foundation

public final class FilePackageByteSource: SVPPackageByteSource, @unchecked Sendable {
    public let length: UInt64
    public let url: URL
    private let descriptor: Int32

    public init(url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw SVPPackageByteSourceError.openFailed(url.path) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_size >= 0 else {
            let code = errno
            close(fd)
            throw SVPPackageByteSourceError.readFailed(code)
        }
        self.url = url
        self.descriptor = fd
        self.length = UInt64(metadata.st_size)
    }

    deinit { close(descriptor) }

    public func read(offset: UInt64, length requestedLength: Int) throws -> Data {
        guard requestedLength >= 0 else { throw SVPPackageByteSourceError.invalidLength }
        guard offset <= length else { throw SVPPackageByteSourceError.outOfRange }
        let (end, overflow) = offset.addingReportingOverflow(UInt64(requestedLength))
        guard !overflow, end <= length, offset <= UInt64(Int64.max) else {
            throw SVPPackageByteSourceError.outOfRange
        }
        guard requestedLength > 0 else { return Data() }

        var result = Data(count: requestedLength)
        var completed = 0
        while completed < requestedLength {
            let (position, positionOverflow) = offset.addingReportingOverflow(UInt64(completed))
            guard !positionOverflow, position <= UInt64(Int64.max) else {
                throw SVPPackageByteSourceError.offsetOverflow
            }
            let count = result.withUnsafeMutableBytes { bytes in
                pread(descriptor, bytes.baseAddress!.advanced(by: completed), requestedLength - completed, off_t(position))
            }
            if count > 0 { completed += count }
            else if count == 0 { break }
            else if errno != EINTR { throw SVPPackageByteSourceError.readFailed(errno) }
        }
        guard completed == requestedLength else {
            throw SVPPackageByteSourceError.shortRead(expected: requestedLength, actual: completed)
        }
        return result
    }
}
