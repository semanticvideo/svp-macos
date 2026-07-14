import AppKit
import SVPReader

enum EmbeddedSVPIFinderServiceRouter {
    static func route(mediaURL: URL, action: Action, coordinator: SVPSupportWindowCoordinator) {
        resolve(mediaURL: mediaURL) { status in
            handle(status: status, action: action, coordinator: coordinator)
        }
    }

    static func resolve(
        mediaURL: URL,
        resolver: @escaping @Sendable (URL) -> SemanticMediaStatus = SemanticMediaResolver.resolve,
        completion: @escaping @Sendable (SemanticMediaStatus) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = resolver(mediaURL)
            DispatchQueue.main.async { completion(status) }
        }
    }

    private static func handle(status: SemanticMediaStatus, action: Action, coordinator: SVPSupportWindowCoordinator) {
        switch status {
        case .embedded(let package):
            switch action {
            case .transcript: coordinator.showEmbeddedTranscript(package: package)
            case .inspector: coordinator.showEmbeddedInspector(package: package)
            case .extract: _ = EmbeddedSVPIExtractor().extract(package: package)
            }
        case .noEmbeddedSvpi:
            show(message: "This media does not contain embedded SVPI.")
        case .invalidEmbedding(let error):
            show(title: "Embedded SVPI integrity error", message: error.description)
        case .unsupportedContainer:
            show(title: "Unsupported media container", message: "This file is not a supported MP4, QuickTime MOV, M4V, or M4A container.")
        }
    }

    enum Action { case transcript, inspector, extract }

    private static func show(title: String = "Embedded SVPI", message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
