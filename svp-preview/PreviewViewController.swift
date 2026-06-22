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

        // Set preferredContentSize early so Quick Look sizes the window correctly.
        // Quick Look reads preferredContentSize before preparePreviewOfFile completes,
        // so we must set it here. Use a 16:9 default that fits the screen.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let maxWidth = screenFrame.width - 120
        let maxHeight = screenFrame.height - 120
        let defaultAspect: CGFloat = 16.0 / 9.0
        let scaledWidth: CGFloat
        let scaledHeight: CGFloat
        if maxWidth / maxHeight > defaultAspect {
            scaledHeight = maxHeight
            scaledWidth = maxHeight * defaultAspect
        } else {
            scaledWidth = maxWidth
            scaledHeight = maxWidth / defaultAspect
        }
        self.preferredContentSize = NSSize(width: scaledWidth, height: scaledHeight)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Quick Look has two contexts:
        // - Finder column preview: window.level == 0 (embedded in Finder)
        // - Quick Look pop-up window: window.level > 0 (floating panel)
        // Only auto-play in the pop-up window, not the Finder column.
        if let window = self.view.window, !hasAutoPlayed {
            qlLogger.info("viewDidAppear: window.frame=\(NSStringFromRect(window.frame), privacy: .public), window.level=\(window.level.rawValue, privacy: .public)")
            qlLogger.info("viewDidAppear: view.frame=\(NSStringFromRect(self.view.frame), privacy: .public), playerView.frame=\(NSStringFromRect(self.playerView.frame), privacy: .public)")
            qlLogger.info("viewDidAppear: playerView.bounds=\(NSStringFromRect(self.playerView.bounds), privacy: .public), playerView.videoBounds=\(NSStringFromRect(self.playerView.videoBounds), privacy: .public)")
            qlLogger.info("viewDidAppear: preferredContentSize=\(NSStringFromSize(self.preferredContentSize), privacy: .public)")
            if window.level.rawValue > 0 {
                hasAutoPlayed = true
                player?.play()
                qlLogger.info("Auto-playing in Quick Look pop-up window")
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        qlLogger.info("viewDidLayout: view.frame=\(NSStringFromRect(self.view.frame), privacy: .public), playerView.frame=\(NSStringFromRect(self.playerView.frame), privacy: .public), playerView.videoBounds=\(NSStringFromRect(self.playerView.videoBounds), privacy: .public)")
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

            // Set preferredContentSize synchronously using the legacy API.
            // The async load API causes preferredContentSize to be set too late —
            // after Quick Look has already sized the window.
            // AVAssetTrack.naturalSize and .preferredTransform are synchronous on local files.
            if let videoTrack = avAsset.tracks(withMediaType: .video).first {
                let naturalSize = videoTrack.naturalSize
                let transform = videoTrack.preferredTransform
                let displaySize = CGSize(
                    width: abs(transform.a) * naturalSize.width + abs(transform.c) * naturalSize.height,
                    height: abs(transform.b) * naturalSize.width + abs(transform.d) * naturalSize.height
                )
                let videoAspect = displaySize.width / displaySize.height
                let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
                let maxWidth = screenFrame.width - 120
                let maxHeight = screenFrame.height - 120
                let scaledWidth: CGFloat
                let scaledHeight: CGFloat
                if maxWidth / maxHeight > videoAspect {
                    scaledHeight = maxHeight
                    scaledWidth = maxHeight * videoAspect
                } else {
                    scaledWidth = maxWidth
                    scaledHeight = maxWidth / videoAspect
                }
                self.preferredContentSize = NSSize(width: scaledWidth, height: scaledHeight)
                qlLogger.info("Video display: \(displaySize.width, privacy: .public)x\(displaySize.height, privacy: .public), screen: \(NSStringFromSize(screenFrame.size), privacy: .public), preferredContentSize: \(scaledWidth, privacy: .public)x\(scaledHeight, privacy: .public)")
            }

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
