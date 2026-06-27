import AVFoundation
import Foundation
import SVPReader
import UniformTypeIdentifiers

final class SVPMediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let reader: SVPReader
    private let mediaInfo: SVPMediaInfo
    private let contentType: String
    private let chunkLength = 1_048_576

    init(reader: SVPReader, mediaInfo: SVPMediaInfo) {
        self.reader = reader
        self.mediaInfo = mediaInfo
        self.contentType = Self.contentType(for: mediaInfo)
        super.init()
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
            loadingRequest.finishLoading()
            return true
        }

        do {
            try respond(to: dataRequest)
            loadingRequest.finishLoading()
        } catch {
            loadingRequest.finishLoading(with: error)
        }

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
    }

    private func respond(to dataRequest: AVAssetResourceLoadingDataRequest) throws {
        let requestedOffset = max(0, dataRequest.requestedOffset)
        let currentRequestOffset = dataRequest.currentOffset == 0 ? requestedOffset : dataRequest.currentOffset
        let currentOffset = UInt64(max(0, currentRequestOffset))
        let requestedLength = UInt64(max(0, dataRequest.requestedLength))

        guard currentOffset < mediaInfo.uncompressedSize else { return }

        let remainingMediaBytes = mediaInfo.uncompressedSize - currentOffset
        let requestedBytes = dataRequest.requestsAllDataToEndOfResource ? remainingMediaBytes : requestedLength
        let length = Int(min(UInt64(chunkLength), requestedBytes, remainingMediaBytes))
        let data = try reader.readMediaDataRange(mediaInfo, offset: currentOffset, length: length)

        guard !data.isEmpty else { return }

        dataRequest.respond(with: data)
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
