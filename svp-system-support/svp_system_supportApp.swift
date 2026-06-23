import AppKit

final class SVPSystemSupportApp: NSObject, NSApplicationDelegate {
    private let videoExtractor = SVPVideoExtractor()
    private let transcriptLoader = SVPTranscriptLoader()
    private let transcriptPresenter = SVPTranscriptWindowPresenter()

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
}
