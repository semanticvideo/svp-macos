import AppKit

final class SVPSystemSupportApp: NSObject, NSApplicationDelegate {
    private let videoExtractor = SVPVideoExtractor()
    private let supportWindowCoordinator = SVPSupportWindowCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let svpURL = urls.first(where: { $0.pathExtension.lowercased() == "svp" }) else {
            NSApp.terminate(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        _ = videoExtractor.extract(from: svpURL)
        NSApp.terminate(nil)
    }

    @objc(extractVideoService:userData:error:)
    func extractVideoService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let svpURL = SVPPasteboardReader.svpURL(from: pasteboard) else {
            error.pointee = "No SVP file was provided."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        _ = videoExtractor.extract(from: svpURL)
        NSApp.terminate(nil)
    }

    @objc(showTranscriptService:userData:error:)
    func showTranscriptService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let svpURL = SVPPasteboardReader.svpURL(from: pasteboard) else {
            error.pointee = "No SVP file was provided."
            return
        }

        supportWindowCoordinator.showTranscript(from: svpURL)
    }

    @objc(inspectSVPService:userData:error:)
    func inspectSVPService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let svpURL = SVPPasteboardReader.svpURL(from: pasteboard) else {
            error.pointee = "No SVP file was provided."
            return
        }

        supportWindowCoordinator.showInspector(for: svpURL)
    }

    @objc(showTranscriptServiceSVPI:userData:error:)
    func showTranscriptServiceSVPI(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let svpiURL = SVPPasteboardReader.svpiURL(from: pasteboard) else {
            error.pointee = "No SVPI file was provided."
            return
        }

        supportWindowCoordinator.showTranscript(from: svpiURL)
    }

    @objc(inspectSVPIService:userData:error:)
    func inspectSVPIService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let svpiURL = SVPPasteboardReader.svpiURL(from: pasteboard) else {
            error.pointee = "No SVPI file was provided."
            return
        }

        supportWindowCoordinator.showInspectorSVPI(for: svpiURL)
    }

    @objc(showEmbeddedSVPITranscriptService:userData:error:)
    func showEmbeddedSVPITranscriptService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let mediaURL = SVPPasteboardReader.semanticMediaURL(from: pasteboard) else {
            error.pointee = "No supported media file was provided."
            return
        }
        EmbeddedSVPIFinderServiceRouter.route(mediaURL: mediaURL, action: .transcript, coordinator: supportWindowCoordinator)
    }

    @objc(extractEmbeddedSVPIService:userData:error:)
    func extractEmbeddedSVPIService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let mediaURL = SVPPasteboardReader.semanticMediaURL(from: pasteboard) else {
            error.pointee = "No supported media file was provided."
            return
        }
        EmbeddedSVPIFinderServiceRouter.route(mediaURL: mediaURL, action: .extract, coordinator: supportWindowCoordinator)
    }

    @objc(inspectEmbeddedSVPIService:userData:error:)
    func inspectEmbeddedSVPIService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let mediaURL = SVPPasteboardReader.semanticMediaURL(from: pasteboard) else {
            error.pointee = "No supported media file was provided."
            return
        }
        EmbeddedSVPIFinderServiceRouter.route(mediaURL: mediaURL, action: .inspector, coordinator: supportWindowCoordinator)
    }
}
