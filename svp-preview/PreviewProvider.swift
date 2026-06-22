import Cocoa
import Quartz
import SVPReader

class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let reader = try SVPReader(url: request.fileURL)
        try reader.validateSVP()

        let mediaURL = try reader.materializePrimaryMedia()
        let reply = QLPreviewReply(fileURL: mediaURL)
        reply.title = request.fileURL.deletingPathExtension().lastPathComponent
        return reply
    }
}
