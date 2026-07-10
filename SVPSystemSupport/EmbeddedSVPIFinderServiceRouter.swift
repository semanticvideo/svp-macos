import AppKit
import SVPReader

enum EmbeddedSVPIFinderServiceRouter {
    static func route(mediaURL: URL, action: Action, coordinator: SVPSupportWindowCoordinator) {
        switch SemanticMediaResolver.resolve(url: mediaURL) {
        case .embedded(let package):
            switch action {
            case .transcript: coordinator.showEmbeddedTranscript(package: package)
            case .inspector: coordinator.showEmbeddedInspector(package: package)
            }
        case .noEmbeddedSvpi:
            show(message: "This media does not contain embedded SVPI.")
        case .invalidEmbedding(let error):
            show(title: "Embedded SVPI integrity error", message: error.description)
        case .unsupportedContainer:
            show(title: "Unsupported media container", message: "This file is not a supported MP4, QuickTime MOV, M4V, or M4A container.")
        }
    }

    enum Action { case transcript, inspector }

    private static func show(title: String = "Embedded SVPI", message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
