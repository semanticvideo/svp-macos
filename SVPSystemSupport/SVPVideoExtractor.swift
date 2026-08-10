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
            let reader = try SVPReader(url: svpURL)
            try reader.validateSVP()

            let mediaInfo = try reader.locatePrimaryMediaAsset()
            let baseName = svpURL.deletingPathExtension().lastPathComponent
            let defaultFileName = "\(baseName).\(mediaInfo.fileExtension)"

            let savePanel = NSSavePanel()
            savePanel.title = "Extract Video from SVP"
            savePanel.prompt = "Extract"
            savePanel.nameFieldStringValue = defaultFileName
            savePanel.directoryURL = svpURL.deletingPathExtension().deletingLastPathComponent()

            let response = savePanel.runModal()
            guard response == .OK, let destURL = savePanel.url else {
                return .cancelled
            }

            try reader.extractMediaData(mediaInfo, to: destURL)

            NSWorkspace.shared.activateFileViewerSelecting([destURL])
            return .extracted
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to extract video"
            alert.informativeText = String(describing: error)
            alert.runModal()
            return .failed
        }
    }
}
