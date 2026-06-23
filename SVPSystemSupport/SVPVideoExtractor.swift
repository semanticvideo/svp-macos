import AppKit
import SVPReader

enum SVPVideoExtractorOutcome {
    case extracted
    case cancelled
    case failed
}

final class SVPVideoExtractor {
    func extract(from svpURL: URL) -> SVPVideoExtractorOutcome {
        do {
            SVPAppLogger.log("App starting extraction from: \(svpURL.path)")
            let reader = try SVPReader(url: svpURL)
            try reader.validateSVP()

            let mediaInfo = try reader.locatePrimaryMediaAsset()
            let mediaData = try reader.readMediaData(mediaInfo)
            SVPAppLogger.log("App loaded media data: \(mediaData.count) bytes")

            let baseName = svpURL.deletingPathExtension().lastPathComponent
            let defaultFileName = "\(baseName).\(mediaInfo.fileExtension)"

            let savePanel = NSSavePanel()
            savePanel.title = "Extract Video from SVP"
            savePanel.prompt = "Extract"
            savePanel.nameFieldStringValue = defaultFileName
            savePanel.directoryURL = svpURL.deletingPathExtension().deletingLastPathComponent()

            SVPAppLogger.log("App presenting save panel")
            let response = savePanel.runModal()
            guard response == .OK, let destURL = savePanel.url else {
                SVPAppLogger.log("App save panel cancelled")
                return .cancelled
            }

            try mediaData.write(to: destURL)
            SVPAppLogger.log("App wrote extracted video to: \(destURL.path)")

            NSWorkspace.shared.activateFileViewerSelecting([destURL])
            return .extracted
        } catch {
            SVPAppLogger.log("App extraction failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to extract video"
            alert.informativeText = String(describing: error)
            alert.runModal()
            return .failed
        }
    }
}
