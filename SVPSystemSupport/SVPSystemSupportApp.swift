import AppKit

final class SVPSystemSupportApp: NSObject, NSApplicationDelegate {
    private let videoExtractor = SVPVideoExtractor()
    private let supportWindowCoordinator = SVPSupportWindowCoordinator()

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

        supportWindowCoordinator.showTranscript(from: svpURL)
    }

    @objc(inspectSVPService:userData:error:)
    func inspectSVPService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received inspector service request")

        guard let svpURL = SVPPasteboardReader.svpURL(from: pasteboard) else {
            SVPAppLogger.log("App inspector service request contained no SVP file URL")
            error.pointee = "No SVP file was provided."
            return
        }

        supportWindowCoordinator.showInspector(for: svpURL)
    }

    @objc(showTranscriptServiceSVPI:userData:error:)
    func showTranscriptServiceSVPI(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received SVPI transcript service request")

        guard let svpiURL = SVPPasteboardReader.svpiURL(from: pasteboard) else {
            SVPAppLogger.log("App SVPI transcript service request contained no SVPI file URL")
            error.pointee = "No SVPI file was provided."
            return
        }

        supportWindowCoordinator.showTranscript(from: svpiURL)
    }

    @objc(inspectSVPIService:userData:error:)
    func inspectSVPIService(_ pasteboard: NSPasteboard, userData: NSString?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        SVPAppLogger.log("App received SVPI inspector service request")

        guard let svpiURL = SVPPasteboardReader.svpiURL(from: pasteboard) else {
            SVPAppLogger.log("App SVPI inspector service request contained no SVPI file URL")
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
