import Cocoa
import Quartz
import AVKit
import AVFoundation
import SVPReader
import os

private let qlLogger = Logger(subsystem: "com.cueit.svp-system-support", category: "QuickLook")

class PreviewViewController: NSViewController, QLPreviewingController {

    private var playerView: AVPlayerView!
    private var player: AVPlayer?
    private var tempDir: URL?
    private var hasAutoPlayed = false

    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        playerView = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        self.view = playerView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Quick Look has two contexts:
        // - Finder column preview: window.level == 0 (embedded in Finder)
        // - Quick Look pop-up window: window.level > 0 (floating panel)
        // Only auto-play in the pop-up window, not the Finder column.
        if let window = self.view.window, !hasAutoPlayed {
            if window.level.rawValue > 0 {
                hasAutoPlayed = true
                player?.play()
                qlLogger.info("Auto-playing in Quick Look pop-up window")
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // Pause immediately when the Quick Look panel closes.
        // viewWillDisappear is not always called promptly in Quick Look extensions,
        // but when it is, we want to stop playback instantly.
        player?.pause()
        qlLogger.info("Quick Look preview disappearing, paused playback")
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        // Fully tear down the player to release file handles on the temp media.
        player?.pause()
        player = nil
        playerView.player = nil
        qlLogger.info("Quick Look preview disappeared, tore down player")
    }

    func preparePreviewOfFile(at url: URL) async throws {
        qlLogger.info("Quick Look preview requested for: \(url.path, privacy: .public)")

        do {
            let reader = try SVPReader(url: url)
            try reader.validateSVP()

            let manifest = try? reader.readManifest()
            qlLogger.info("SVP manifest: package=\(manifest?.packageID ?? "?", privacy: .public)")

            let mediaInfo = try reader.locatePrimaryMediaAsset()
            qlLogger.info("Primary media: \(mediaInfo.mediaPath, privacy: .public), ext=\(mediaInfo.fileExtension, privacy: .public)")

            guard mediaInfo.likelyPlayableByAVFoundation else {
                qlLogger.error("Media not likely playable by AVFoundation: \(mediaInfo.fileExtension, privacy: .public)")
                showError("Unsupported codec: \(mediaInfo.fileExtension)")
                return
            }

            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("svp-ql-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let mediaURL = dir.appendingPathComponent(mediaInfo.mediaFileName)
            let mediaData = try reader.readMediaData(mediaInfo)
            try mediaData.write(to: mediaURL)

            self.tempDir = dir

            qlLogger.info("Materialized \(mediaData.count) bytes to \(mediaURL.path, privacy: .public)")

            let avAsset = AVURLAsset(url: mediaURL)
            let playerItem = AVPlayerItem(asset: avAsset)
            let avPlayer = AVPlayer(playerItem: playerItem)

            self.player = avPlayer
            self.playerView.player = avPlayer

            qlLogger.info("Quick Look preview ready, waiting for window context")
        } catch let error as SVPError {
            qlLogger.error("SVP error: \(String(describing: error), privacy: .public)")
            showError(String(describing: error))
        } catch {
            qlLogger.error("Unexpected error: \(String(describing: error), privacy: .public)")
            showError("I/O error: \(String(describing: error))")
        }
    }

    private func showError(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        playerView.removeFromSuperview()
        view = label

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    deinit {
        player?.pause()
        player = nil
        if let tempDir {
            SVPReader.cleanupMaterializedMedia(at: tempDir)
        }
    }
}
