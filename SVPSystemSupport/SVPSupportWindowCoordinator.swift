import AppKit
import Darwin

final class SVPSupportWindowCoordinator {
    private let transcriptLoader = SVPTranscriptLoader()
    private let transcriptPresenter = SVPTranscriptWindowPresenter()
    private var inspectorWindowControllers: [SVPInspectorWindowController] = []

    init() {
        transcriptPresenter.onClose = { [weak self] in
            self?.handleSupportWindowClosed(reason: "transcript")
        }
    }

    func showTranscript(from svpURL: URL) {
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

    func showInspector(for svpURL: URL) {
        showInspector(for: svpURL, formatLabel: "SVP")
    }

    func showInspectorSVPI(for svpiURL: URL) {
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
            self?.handleSupportWindowClosed(reason: "inspector")
        }
        inspectorWindowControllers.append(windowController)
        windowController.present()
    }

    private func handleSupportWindowClosed(reason: String) {
        DispatchQueue.main.async { [weak self] in
            self?.terminateIfNoSupportWindowsRemain(reason: reason)
        }
    }

    private func terminateIfNoSupportWindowsRemain(reason: String) {
        let inspectorCount = inspectorWindowControllers.count
        let transcriptCount = transcriptPresenter.windowCount

        guard inspectorCount == 0, transcriptCount == 0 else { return }
        guard !isRunningUnderDebugger else {
            SVPAppLogger.log("No inspector or transcript windows remain; debugger attached, skipping app termination")
            return
        }

        SVPAppLogger.log("No inspector or transcript windows remain; terminating app")
        NSApp.terminate(nil)
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
