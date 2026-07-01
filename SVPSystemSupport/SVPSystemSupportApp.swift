import AppKit

final class SVPSystemSupportApp: NSObject, NSApplicationDelegate {
    private let videoExtractor = SVPVideoExtractor()
    private let transcriptLoader = SVPTranscriptLoader()
    private let transcriptPresenter = SVPTranscriptWindowPresenter()
    private var inspectorWindowControllers: [SVPInspectorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        SVPAppLogger.log("App did finish launching")
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SVPAppLogger.log("App should handle reopen")
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        SVPAppLogger.log("App received open URLs: \(urls.map(\.path).joined(separator: ", "))")
        guard let svpURL = urls.first(where: { $0.pathExtension.lowercased() == "svp" }) else {
            SVPAppLogger.log("App received no SVP open URLs")
            NSApp.terminate(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        _ = videoExtractor.extract(from: svpURL)
        NSApp.terminate(nil)
    }

    @objc(extractVideoService:userData:error:)
    func extractVideoService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received service request")

        guard let svpURL = SVPPasteboardReader.svpURL(from: pasteboard) else {
            SVPAppLogger.log("App service request contained no SVP file URL")
            error.pointee = "No SVP file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        _ = videoExtractor.extract(from: svpURL)
        NSApp.terminate(nil)
    }

    @objc(showTranscriptService:userData:error:)
    func showTranscriptService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received transcript service request")

        guard let svpURL = SVPPasteboardReader.svpURL(from: pasteboard) else {
            SVPAppLogger.log("App transcript service request contained no SVP file URL")
            error.pointee = "No SVP file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        showTranscript(from: svpURL)
    }

    private func showTranscript(from svpURL: URL) {
        do {
            let transcript = try transcriptLoader.loadTranscript(from: svpURL)
            let videoTitle = svpURL.deletingPathExtension().lastPathComponent
            transcriptPresenter.present(title: "\(videoTitle) Transcript", text: transcript)
        } catch {
            SVPAppLogger.log("App transcript failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to show transcript"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }

    @objc(inspectSVPService:userData:error:)
    func inspectSVPService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received inspector service request")

        guard let svpURL = SVPPasteboardReader.svpURL(from: pasteboard) else {
            SVPAppLogger.log("App inspector service request contained no SVP file URL")
            error.pointee = "No SVP file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        showInspector(for: svpURL)
    }

    private func showInspector(for svpURL: URL) {
        showInspector(for: svpURL, formatLabel: "SVP")
    }

    private func showInspectorSVPI(for svpiURL: URL) {
        showInspector(for: svpiURL, formatLabel: "SVPI")
    }

    private func showInspector(for url: URL, formatLabel: String) {
        SVPAppLogger.log("App opening inspector for: \(url.path)")
        let data = SVPInspectorData.load(from: url)

        if let error = data.loadError {
            SVPAppLogger.log("App inspector load failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to open \(formatLabel) Inspector"
            alert.informativeText = error
            alert.runModal()
            return
        }

        let title = "\(url.deletingPathExtension().lastPathComponent) — \(formatLabel) Inspector"
        let windowController = SVPInspectorWindowController(data: data, windowTitle: title)
        windowController.onClose = { [weak self, weak windowController] in
            guard let windowController else { return }
            self?.inspectorWindowControllers.removeAll { $0 === windowController }
        }
        inspectorWindowControllers.append(windowController)
        windowController.present()
    }

    @objc(showTranscriptServiceSVPI:userData:error:)
    func showTranscriptServiceSVPI(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received SVPI transcript service request")

        guard let svpiURL = SVPPasteboardReader.svpiURL(from: pasteboard) else {
            SVPAppLogger.log("App SVPI transcript service request contained no SVPI file URL")
            error.pointee = "No SVPI file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        showTranscript(from: svpiURL)
    }

    @objc(inspectSVPIService:userData:error:)
    func inspectSVPIService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received SVPI inspector service request")

        guard let svpiURL = SVPPasteboardReader.svpiURL(from: pasteboard) else {
            SVPAppLogger.log("App SVPI inspector service request contained no SVPI file URL")
            error.pointee = "No SVPI file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        showInspectorSVPI(for: svpiURL)
    }
}
