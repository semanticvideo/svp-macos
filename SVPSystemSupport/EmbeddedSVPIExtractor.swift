import AppKit
import SVPReader

enum EmbeddedSVPIExtractorOutcome {
    case extracted
    case cancelled
    case failed
}

final class EmbeddedSVPIExtractor {
    func extract(package: SVPPackageDescriptor) -> EmbeddedSVPIExtractorOutcome {
        let mediaURL = package.mediaURL
        let defaultFileName = "\(mediaURL.deletingPathExtension().lastPathComponent).svpi"

        let savePanel = NSSavePanel()
        savePanel.title = "Extract Embedded SVPI"
        savePanel.prompt = "Extract"
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.directoryURL = mediaURL.deletingLastPathComponent()

        NSApp.activate(ignoringOtherApps: true)
        let response = savePanel.runModal()
        guard response == .OK, let destinationURL = savePanel.url else {
            SVPAppLogger.log("App embedded SVPI save panel cancelled")
            return .cancelled
        }

        do {
            try Self.write(package: package, to: destinationURL)
            SVPAppLogger.log("App wrote extracted SVPI to: \(destinationURL.path)")
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            return .extracted
        } catch {
            SVPAppLogger.log("App embedded SVPI extraction failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to extract SVPI"
            alert.informativeText = String(describing: error)
            alert.runModal()
            return .failed
        }
    }

    static func write(
        package: SVPPackageDescriptor,
        to destinationURL: URL,
        bufferSize: Int = 1_048_576
    ) throws {
        guard bufferSize > 0 else { throw EmbeddedSVPIExtractorError.invalidBufferSize }
        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw EmbeddedSVPIExtractorError.cannotCreateDestination(destinationURL)
        }

        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        do {
            var offset: UInt64 = 0
            while offset < package.source.length {
                let count = Int(min(UInt64(bufferSize), package.source.length - offset))
                let data = try package.source.read(offset: offset, length: count)
                guard !data.isEmpty else { throw EmbeddedSVPIExtractorError.unexpectedEndOfSource }
                try output.write(contentsOf: data)
                offset += UInt64(data.count)
            }
            try output.close()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }
}

private enum EmbeddedSVPIExtractorError: LocalizedError {
    case invalidBufferSize
    case cannotCreateDestination(URL)
    case unexpectedEndOfSource

    var errorDescription: String? {
        switch self {
        case .invalidBufferSize:
            return "The extraction buffer size is invalid."
        case .cannotCreateDestination(let url):
            return "The destination file could not be created at \(url.path)."
        case .unexpectedEndOfSource:
            return "The embedded SVPI payload ended before extraction completed."
        }
    }
}
