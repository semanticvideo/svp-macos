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
            return .cancelled
        }

        do {
            try Self.write(package: package, to: destinationURL)
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            return .extracted
        } catch {
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
        try write(
            source: package.source,
            sourceMediaURL: package.mediaURL,
            to: destinationURL,
            bufferSize: bufferSize
        )
    }

    static func write(
        source: any SVPPackageByteSource,
        sourceMediaURL: URL,
        to destinationURL: URL,
        bufferSize: Int
    ) throws {
        guard bufferSize > 0 else { throw EmbeddedSVPIExtractorError.invalidBufferSize }
        guard !pointsToSameFile(sourceMediaURL, destinationURL) else {
            throw EmbeddedSVPIExtractorError.destinationMatchesSource
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-embedded-svpi-extraction-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw EmbeddedSVPIExtractorError.cannotCreateDestination(destinationURL)
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let output = try FileHandle(forWritingTo: temporaryURL)
        do {
            var offset: UInt64 = 0
            while offset < source.length {
                let count = Int(min(UInt64(bufferSize), source.length - offset))
                let data = try source.read(offset: offset, length: count)
                guard !data.isEmpty else { throw EmbeddedSVPIExtractorError.unexpectedEndOfSource }
                try output.write(contentsOf: data)
                offset += UInt64(data.count)
            }
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private static func pointsToSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhs = lhs.standardizedFileURL.resolvingSymlinksInPath()
        let rhs = rhs.standardizedFileURL.resolvingSymlinksInPath()
        if lhs == rhs { return true }

        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard
            let lhsID = try? lhs.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject,
            let rhsID = try? rhs.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject
        else { return false }
        return lhsID.isEqual(rhsID)
    }
}

private enum EmbeddedSVPIExtractorError: LocalizedError {
    case invalidBufferSize
    case cannotCreateDestination(URL)
    case destinationMatchesSource
    case unexpectedEndOfSource

    var errorDescription: String? {
        switch self {
        case .invalidBufferSize:
            return "The extraction buffer size is invalid."
        case .cannotCreateDestination(let url):
            return "The destination file could not be created at \(url.path)."
        case .destinationMatchesSource:
            return "The embedded SVPI cannot replace its source media file."
        case .unexpectedEndOfSource:
            return "The embedded SVPI payload ended before extraction completed."
        }
    }
}
