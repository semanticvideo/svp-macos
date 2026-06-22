import AppKit
import SVPReader

class SVPSystemSupportApp: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("App did finish launching")
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log("App should handle reopen")
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        log("App received open URLs: \(urls.map(\.path).joined(separator: ", "))")
        guard let svpURL = urls.first(where: { $0.pathExtension.lowercased() == "svp" }) else {
            log("App received no SVP open URLs")
            NSApp.terminate(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        extractVideo(from: svpURL)
    }

    @objc(extractVideoService:userData:error:)
    func extractVideoService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        log("App received service request")

        guard let svpURL = svpURL(from: pasteboard) else {
            log("App service request contained no SVP file URL")
            error.pointee = "No SVP file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        extractVideo(from: svpURL)
    }

    @objc(showTranscriptService:userData:error:)
    func showTranscriptService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        log("App received transcript service request")

        guard let svpURL = svpURL(from: pasteboard) else {
            log("App transcript service request contained no SVP file URL")
            error.pointee = "No SVP file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        showTranscript(from: svpURL)
    }

    private func svpURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["com.semanticvideo.svp"]
        ]

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first { $0.pathExtension.lowercased() == "svp" }
    }

    private func extractVideo(from svpURL: URL) {
        do {
            log("App starting extraction from: \(svpURL.path)")
            let reader = try SVPReader(url: svpURL)
            try reader.validateSVP()

            let mediaInfo = try reader.locatePrimaryMediaAsset()
            let mediaData = try reader.readMediaData(mediaInfo)
            log("App loaded media data: \(mediaData.count) bytes")

            let baseName = svpURL.deletingPathExtension().lastPathComponent
            let defaultFileName = "\(baseName).\(mediaInfo.fileExtension)"

            let savePanel = NSSavePanel()
            savePanel.title = "Extract Video from SVP"
            savePanel.prompt = "Extract"
            savePanel.nameFieldStringValue = defaultFileName
            savePanel.directoryURL = svpURL.deletingPathExtension().deletingLastPathComponent()

            log("App presenting save panel")
            let response = savePanel.runModal()
            guard response == .OK, let destURL = savePanel.url else {
                log("App save panel cancelled")
                NSApp.terminate(nil)
                return
            }

            try mediaData.write(to: destURL)
            log("App wrote extracted video to: \(destURL.path)")

            NSWorkspace.shared.activateFileViewerSelecting([destURL])
            NSApp.terminate(nil)
        } catch {
            log("App extraction failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to extract video"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func showTranscript(from svpURL: URL) {
        do {
            log("App loading transcript from: \(svpURL.path)")
            let reader = try SVPReader(url: svpURL)
            try reader.validateSVP()
            let transcript = try reader.readTranscriptText()
            log("App loaded transcript: \(transcript.count) characters")

            let alert = NSAlert()
            alert.messageText = "SVP Transcript"
            alert.addButton(withTitle: "Done")
            alert.accessoryView = transcriptView(text: transcript)
            alert.runModal()
        } catch {
            log("App transcript failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to show transcript"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }

    private func transcriptView(text: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.string = text
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width, .height]

        scrollView.documentView = textView
        return scrollView
    }

    private func log(_ message: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cueit.svp-system-support") else { return }

        let logURL = containerURL.appendingPathComponent("svp_extract.log")
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
