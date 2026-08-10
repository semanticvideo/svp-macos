import AppKit
import Darwin
import SVPReader

final class SVPSupportWindowCoordinator {
    private let transcriptLoader = SVPTranscriptLoader()
    private let transcriptPresenter = SVPTranscriptWindowPresenter()
    private var inspectorWindowControllers: [SVPInspectorWindowController] = []

    init() {
        transcriptPresenter.onClose = { [weak self] in
            self?.handleSupportWindowClosed()
        }
    }

    func showTranscript(from svpURL: URL) {
        let videoTitle = svpURL.deletingPathExtension().lastPathComponent
        prepareForSupportWindowPresentation()
        let window = transcriptPresenter.presentLoading(title: "\(videoTitle) Transcript")

        DispatchQueue.global(qos: .userInitiated).async { [transcriptLoader, weak self, weak window] in
            let result: Result<String, Error>
            do {
                result = .success(try transcriptLoader.loadTranscript(from: svpURL))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self, let window, self.transcriptPresenter.contains(window) else { return }

                switch result {
                case .success(let transcript):
                    self.transcriptPresenter.completeLoading(window: window, text: transcript)
                case .failure(let error):
                    self.transcriptPresenter.close(window: window)
                    let alert = NSAlert()
                    alert.messageText = "Failed to show transcript"
                    alert.informativeText = String(describing: error)
                    alert.runModal()
                }
            }
        }
    }

    func showInspector(for svpURL: URL) {
        showInspector(for: svpURL, formatLabel: "SVP")
    }

    func showInspectorSVPI(for svpiURL: URL) {
        showInspector(for: svpiURL, formatLabel: "SVPI")
    }

    func showEmbeddedTranscript(package: SVPPackageDescriptor) {
        let title = package.mediaURL.deletingPathExtension().lastPathComponent
        prepareForSupportWindowPresentation()
        let window = transcriptPresenter.presentLoading(title: "\(title) Transcript")
        DispatchQueue.global(qos: .userInitiated).async { [transcriptLoader, weak self, weak window] in
            let result = Result { try transcriptLoader.loadTranscript(from: package) }
            DispatchQueue.main.async {
                guard let self, let window, self.transcriptPresenter.contains(window) else { return }
                switch result {
                case .success(let transcript): self.transcriptPresenter.completeLoading(window: window, text: transcript)
                case .failure(let error):
                    self.transcriptPresenter.close(window: window)
                    let alert = NSAlert(); alert.messageText = "Failed to show transcript"; alert.informativeText = String(describing: error); alert.runModal()
                }
            }
        }
    }

    func showEmbeddedInspector(package: SVPPackageDescriptor) {
        showInspector(for: package.mediaURL, formatLabel: "Embedded SVPI", package: package)
    }

    private func showInspector(for url: URL, formatLabel: String, package: SVPPackageDescriptor? = nil) {
        let viewModel = SVPInspectorViewModel(fileURL: url, formatLabel: formatLabel, package: package)
        let windowController = SVPInspectorWindowController(viewModel: viewModel)
        windowController.onClose = { [weak self, weak windowController] in
            guard let windowController else { return }
            self?.inspectorWindowControllers.removeAll { $0 === windowController }
            self?.handleSupportWindowClosed()
        }
        inspectorWindowControllers.append(windowController)
        prepareForSupportWindowPresentation()
        windowController.present()
    }

    private func prepareForSupportWindowPresentation() {
        let currentPolicy = NSApp.activationPolicy()
        if currentPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleSupportWindowClosed() {
        DispatchQueue.main.async { [weak self] in
            self?.terminateIfNoSupportWindowsRemain()
        }
    }

    private func terminateIfNoSupportWindowsRemain() {
        let inspectorCount = inspectorWindowControllers.count
        let transcriptCount = transcriptPresenter.windowCount

        guard inspectorCount == 0, transcriptCount == 0 else { return }
        demoteAppAfterSupportWindowsClose()

        guard !isRunningUnderDebugger else {
            return
        }

        NSApp.terminate(nil)
    }

    private func demoteAppAfterSupportWindowsClose() {
        let currentPolicy = NSApp.activationPolicy()
        guard currentPolicy == .regular else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
    }

    private var isRunningUnderDebugger: Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride

        let result = mib.withUnsafeMutableBufferPointer { mibPointer in
            sysctl(mibPointer.baseAddress, u_int(mibPointer.count), &info, &size, nil, 0)
        }

        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
