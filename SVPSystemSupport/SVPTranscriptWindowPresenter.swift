import AppKit

final class SVPTranscriptWindowPresenter: NSObject, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var textViews: [ObjectIdentifier: NSTextView] = [:]
    private var statusLabels: [ObjectIdentifier: NSTextField] = [:]
    private var progressIndicators: [ObjectIdentifier: NSProgressIndicator] = [:]
    var onClose: (() -> Void)?
    var windowCount: Int { windows.count }

    func presentLoading(title: String) -> NSWindow {
        present(title: title, text: "", status: "Loading transcript...", isLoading: true)
    }

    func completeLoading(window: NSWindow, text: String) {
        guard contains(window) else { return }
        let identifier = ObjectIdentifier(window)
        progressIndicators[identifier]?.stopAnimation(nil)
        progressIndicators[identifier]?.isHidden = true
        statusLabels[identifier]?.stringValue = ""
        statusLabels[identifier]?.isHidden = true
        textViews[identifier]?.string = text
    }

    func close(window: NSWindow) {
        guard contains(window) else { return }
        window.performClose(nil)
    }

    func contains(_ window: NSWindow) -> Bool {
        windows.contains { $0 === window }
    }

    @discardableResult
    private func present(title: String, text: String, status: String, isLoading: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let backgroundView: NSView
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView = glassView
        } else {
            let vibrancyView = NSVisualEffectView()
            vibrancyView.material = .hudWindow
            vibrancyView.blendingMode = .behindWindow
            vibrancyView.state = .active
            vibrancyView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView = vibrancyView
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        if isLoading {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.isHidden = true
        }

        let statusLabel = NSTextField(labelWithString: status)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.isHidden = !isLoading
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.string = text
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView

        let doneButton = NSButton(title: "Done", target: self, action: #selector(transcriptWindowDone(_:)))
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let contentView = window.contentView!
        contentView.addSubview(backgroundView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(scrollView)
        contentView.addSubview(doneButton)
        scrollView.addSubview(progressIndicator)
        scrollView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -12),

            progressIndicator.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -12),
            statusLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),

            doneButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])

        windows.append(window)
        let identifier = ObjectIdentifier(window)
        textViews[identifier] = textView
        statusLabels[identifier] = statusLabel
        progressIndicators[identifier] = progressIndicator
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @objc private func transcriptWindowDone(_ sender: NSButton) {
        sender.window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
        let identifier = ObjectIdentifier(window)
        textViews[identifier] = nil
        statusLabels[identifier] = nil
        progressIndicators[identifier] = nil
        window.delegate = nil
        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        onClose?()
    }
}
