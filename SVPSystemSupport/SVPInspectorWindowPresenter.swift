import AppKit
import SwiftUI

final class SVPInspectorWindowPresenter: NSObject, NSWindowDelegate {
    func present(title: String, data: SVPInspectorData) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.minSize = NSSize(width: 600, height: 400)

        let hostingController = NSHostingController(rootView: SVPInspectorView(data: data))
        window.contentViewController = hostingController

        NSApp.runModal(for: window)
        window.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: .cancel)
    }
}
