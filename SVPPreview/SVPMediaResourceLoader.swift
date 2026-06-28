import AVFoundation
import Foundation
import SVPReader
import UniformTypeIdentifiers

final class SVPMediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let reader: SVPReader
    private let mediaInfo: SVPMediaInfo
    private let contentType: String
    private let chunkLength = 1_048_576
    private let loadingRequestLock = NSLock()
    private var cancelledLoadingRequests = Set<ObjectIdentifier>()
    private let rangeResponseQueue: OperationQueue
    private let openEndedResponseQueue: OperationQueue
    private let progressLogInterval: UInt64 = 64 * 1_048_576

    init(reader: SVPReader, mediaInfo: SVPMediaInfo) {
        self.reader = reader
        self.mediaInfo = mediaInfo
        self.contentType = Self.contentType(for: mediaInfo)
        self.rangeResponseQueue = OperationQueue()
        self.rangeResponseQueue.name = "com.cueit.svp-system-support.preview.media-range-response"
        self.rangeResponseQueue.qualityOfService = .userInitiated
        self.rangeResponseQueue.maxConcurrentOperationCount = 4
        self.openEndedResponseQueue = OperationQueue()
        self.openEndedResponseQueue.name = "com.cueit.svp-system-support.preview.media-open-ended-response"
        self.openEndedResponseQueue.qualityOfService = .utility
        self.openEndedResponseQueue.maxConcurrentOperationCount = 1
        super.init()
        log("init media=\(mediaInfo.mediaFileName) size=\(mediaInfo.uncompressedSize) type=\(contentType)")
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let contentInformationRequest = loadingRequest.contentInformationRequest {
            contentInformationRequest.contentType = contentType
            contentInformationRequest.contentLength = Int64(mediaInfo.uncompressedSize)
            contentInformationRequest.isByteRangeAccessSupported = true
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            log("finish content-info-only id=\(requestIDString(loadingRequest))")
            loadingRequest.finishLoading()
            return true
        }

        let requestID = ObjectIdentifier(loadingRequest)
        loadingRequestLock.lock()
        cancelledLoadingRequests.remove(requestID)
        loadingRequestLock.unlock()

        let requestKind = dataRequest.requestsAllDataToEndOfResource ? "open" : "range"
        log(
            "enqueue kind=\(requestKind) id=\(requestIDString(loadingRequest)) requestedOffset=\(dataRequest.requestedOffset) currentOffset=\(dataRequest.currentOffset) requestedLength=\(dataRequest.requestedLength) allToEnd=\(dataRequest.requestsAllDataToEndOfResource) rangeQueue=\(rangeResponseQueue.operationCount) openQueue=\(openEndedResponseQueue.operationCount)"
        )

        let queue = dataRequest.requestsAllDataToEndOfResource ? openEndedResponseQueue : rangeResponseQueue
        queue.addOperation { [weak self, loadingRequest, dataRequest] in
            self?.respond(to: loadingRequest, dataRequest: dataRequest, kind: requestKind)
        }

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        loadingRequestLock.lock()
        cancelledLoadingRequests.insert(ObjectIdentifier(loadingRequest))
        loadingRequestLock.unlock()
        log("cancel id=\(requestIDString(loadingRequest))")
    }

    private func respond(
        to loadingRequest: AVAssetResourceLoadingRequest,
        dataRequest: AVAssetResourceLoadingDataRequest,
        kind: String
    ) {
        let requestID = ObjectIdentifier(loadingRequest)
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let bytesResponded = try respond(to: dataRequest, requestID: requestID, kind: kind)
            guard !isCancelled(requestID), !loadingRequest.isCancelled else {
                log(
                    "cancelled-before-finish kind=\(kind) id=\(requestIDString(loadingRequest)) bytes=\(bytesResponded) elapsed=\(elapsedSince(startTime))"
                )
                clearCancellation(requestID)
                return
            }

            loadingRequest.finishLoading()
            log(
                "finish kind=\(kind) id=\(requestIDString(loadingRequest)) bytes=\(bytesResponded) finalCurrentOffset=\(dataRequest.currentOffset) elapsed=\(elapsedSince(startTime))"
            )
            clearCancellation(requestID)
        } catch {
            guard !isCancelled(requestID), !loadingRequest.isCancelled else {
                log(
                    "cancelled-after-error kind=\(kind) id=\(requestIDString(loadingRequest)) error=\(error) elapsed=\(elapsedSince(startTime))"
                )
                clearCancellation(requestID)
                return
            }

            log("error kind=\(kind) id=\(requestIDString(loadingRequest)) error=\(error) elapsed=\(elapsedSince(startTime))")
            loadingRequest.finishLoading(with: error)
            clearCancellation(requestID)
        }
    }

    private func respond(
        to dataRequest: AVAssetResourceLoadingDataRequest,
        requestID: ObjectIdentifier,
        kind: String
    ) throws -> UInt64 {
        let requestedOffset = max(0, dataRequest.requestedOffset)
        let currentRequestOffset = dataRequest.currentOffset == 0 ? requestedOffset : dataRequest.currentOffset
        var currentOffset = UInt64(max(0, currentRequestOffset))

        guard currentOffset < mediaInfo.uncompressedSize else { return 0 }

        let requestedEndOffset: UInt64
        if dataRequest.requestsAllDataToEndOfResource {
            requestedEndOffset = mediaInfo.uncompressedSize
        } else {
            let requestedLength = UInt64(max(0, dataRequest.requestedLength))
            requestedEndOffset = min(mediaInfo.uncompressedSize, UInt64(max(0, requestedOffset)) + requestedLength)
        }

        var bytesResponded: UInt64 = 0
        var nextProgressLogOffset = currentOffset + progressLogInterval

        while currentOffset < requestedEndOffset {
            guard !isCancelled(requestID) else { return bytesResponded }

            let remainingRequestedBytes = requestedEndOffset - currentOffset
            let length = Int(min(UInt64(chunkLength), remainingRequestedBytes))
            let readStartTime = CFAbsoluteTimeGetCurrent()
            let data = try reader.readMediaDataRange(mediaInfo, offset: currentOffset, length: length)
            let readElapsed = CFAbsoluteTimeGetCurrent() - readStartTime

            if readElapsed > 0.2 {
                log(
                    "slow-read kind=\(kind) offset=\(currentOffset) requestedLength=\(length) actualLength=\(data.count) elapsed=\(formatSeconds(readElapsed))"
                )
            }

            guard !data.isEmpty else {
                log("empty-read kind=\(kind) offset=\(currentOffset) requestedLength=\(length)")
                return bytesResponded
            }

            guard !isCancelled(requestID) else { return bytesResponded }
            dataRequest.respond(with: data)
            bytesResponded += UInt64(data.count)

            let nextOffset = UInt64(max(0, dataRequest.currentOffset))
            currentOffset = nextOffset > currentOffset ? nextOffset : currentOffset + UInt64(data.count)

            if currentOffset >= nextProgressLogOffset {
                log(
                    "progress kind=\(kind) id=\(requestID) currentOffset=\(currentOffset) bytes=\(bytesResponded) targetOffset=\(requestedEndOffset)"
                )
                nextProgressLogOffset = currentOffset + progressLogInterval
            }
        }

        return bytesResponded
    }

    private func isCancelled(_ requestID: ObjectIdentifier) -> Bool {
        loadingRequestLock.lock()
        defer { loadingRequestLock.unlock() }
        return cancelledLoadingRequests.contains(requestID)
    }

    private func clearCancellation(_ requestID: ObjectIdentifier) {
        loadingRequestLock.lock()
        cancelledLoadingRequests.remove(requestID)
        loadingRequestLock.unlock()
    }

    private func requestIDString(_ loadingRequest: AVAssetResourceLoadingRequest) -> String {
        String(describing: ObjectIdentifier(loadingRequest))
    }

    private func elapsedSince(_ startTime: CFAbsoluteTime) -> String {
        Self.formatSeconds(CFAbsoluteTimeGetCurrent() - startTime)
    }

    private func formatSeconds(_ value: CFTimeInterval) -> String {
        Self.formatSeconds(value)
    }

    private static func formatSeconds(_ value: CFTimeInterval) -> String {
        String(format: "%.3fs", value)
    }

    private func log(_ message: String) {
        Self.log(message)
    }

    private static func log(_ message: String) {
        fputs("SVPQL \(Date()) \(message)\n", stderr)
        fflush(stderr)
    }

    private static func contentType(for mediaInfo: SVPMediaInfo) -> String {
        if let type = UTType(filenameExtension: mediaInfo.fileExtension) {
            return type.identifier
        }

        switch mediaInfo.fileExtension.lowercased() {
        case "mov":
            return "com.apple.quicktime-movie"
        case "mp4", "m4v":
            return "public.mpeg-4"
        default:
            return "public.movie"
        }
    }
}
