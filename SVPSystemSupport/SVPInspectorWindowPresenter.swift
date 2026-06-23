import AppKit
import Quartz
import SwiftUI

// MARK: - Window Controller

final class SVPInspectorWindowController: NSWindowController {
    private let splitViewController: SVPInspectorSplitViewController
    private let toolbarProvider: SVPInspectorToolbarProvider
    private var quickLookDataSource: QLPreviewPanelDataSource?
    private var quickLookStartIndex: Int = 0

    private enum Metrics {
        static let contentSize = NSSize(width: 900, height: 650)
        static let minimumSize = NSSize(width: 600, height: 400)
    }

    init(data: SVPInspectorData, windowTitle: String) {
        let splitViewController = SVPInspectorSplitViewController(data: data)
        let toolbarProvider = SVPInspectorToolbarProvider(
            toggleSidebar: { splitViewController.toggleSidebar(nil) },
            fileName: windowTitle
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = Metrics.minimumSize
        window.contentViewController = splitViewController
        window.isReleasedWhenClosed = false
        self.splitViewController = splitViewController
        self.toolbarProvider = toolbarProvider

        super.init(window: window)

        window.toolbar = toolbarProvider.makeToolbar()
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SVPInspectorWindowController does not support storyboards.")
    }

    func presentModal() {
        guard let window else { return }
        NSApp.runModal(for: window)
        window.orderOut(nil)
    }

    // MARK: - Quick Look

    func showQuickLook(dataSource: QLPreviewPanelDataSource, startIndex: Int) {
        quickLookDataSource = dataSource
        quickLookStartIndex = startIndex

        let panel = QLPreviewPanel.shared()!
        if panel.isVisible { panel.close() }

        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - QLPreviewPanelController (informal protocol)

extension SVPInspectorWindowController {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookDataSource
        if let ds = quickLookDataSource as? EvidenceCropQuickLookController {
            panel.currentPreviewItemIndex = min(quickLookStartIndex, max(0, ds.tempURLs.count - 1))
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        quickLookDataSource = nil
    }
}

extension SVPInspectorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: .cancel)
    }
}

// MARK: - Toolbar Provider

private final class SVPInspectorToolbarProvider: NSObject, NSToolbarDelegate {
    private let toggleSidebar: () -> Void
    private let fileName: String

    private enum Metrics {
        static let toolbarIdentifier = NSToolbar.Identifier("SVPInspectorToolbar")
        static let sidebarToggleItem = NSToolbarItem.Identifier("SVPInspectorSidebarToggleItem")
        static let fileNameItem = NSToolbarItem.Identifier("SVPInspectorFileNameItem")
        static let sidebarToggleSize = NSSize(width: 32, height: 28)
    }

    init(
        toggleSidebar: @escaping () -> Void,
        fileName: String
    ) {
        self.toggleSidebar = toggleSidebar
        self.fileName = fileName
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: Metrics.toolbarIdentifier)
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            Metrics.sidebarToggleItem,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            Metrics.fileNameItem
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            Metrics.sidebarToggleItem,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            Metrics.fileNameItem
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .sidebarTrackingSeparator, .flexibleSpace:
            return nil
        case Metrics.sidebarToggleItem:
            return makeSidebarToggleItem(itemIdentifier: itemIdentifier)
        case Metrics.fileNameItem:
            return makeFileNameItem(itemIdentifier: itemIdentifier)
        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }

    private func makeSidebarToggleItem(itemIdentifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let button = NSButton(
            image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar") ?? NSImage(),
            target: self,
            action: #selector(sidebarToggleSelected)
        )
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Metrics.sidebarToggleSize.width),
            button.heightAnchor.constraint(equalToConstant: Metrics.sidebarToggleSize.height)
        ])

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Toggle Sidebar"
        item.paletteLabel = "Toggle Sidebar"
        item.toolTip = "Toggle Sidebar"
        item.view = button
        return item
    }

    private func makeFileNameItem(itemIdentifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let label = NSTextField(labelWithString: fileName)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.controlAccentColor
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .right

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = fileName
        item.paletteLabel = fileName
        item.view = label
        return item
    }

    @objc private func sidebarToggleSelected() {
        toggleSidebar()
    }
}
