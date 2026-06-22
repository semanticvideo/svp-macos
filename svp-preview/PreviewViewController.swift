import Cocoa
import Quartz
import AVKit
import AVFoundation
import SVPReader

class PreviewViewController: NSViewController, QLPreviewingController {

    private var playerView: AVPlayerView!
    private var player: AVPlayer?
    private var tempDir: URL?
    private var hasAutoPlayed = false
    private var visibilityTimer: Timer?
    private var wasVisibleInPopup = false

    deinit {
        visibilityTimer?.invalidate()
        player?.pause()
        player = nil
        if let tempDir {
            SVPReader.cleanupMaterializedMedia(at: tempDir)
        }
    }

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
            if window.level.rawValue > 0 {
                hasAutoPlayed = true
                wasVisibleInPopup = true
                player?.play()

                // Quick Look does not call viewWillDisappear/viewDidDisappear when the user
                // navigates to a different file with arrow keys. The only reliable way to detect
                // that our preview is no longer the active one is to poll window.level.
                // When Quick Look switches to a different file type, it swaps in a different
                // extension's view controller, and our window.level drops to 0 or the window
                // changes. This is a known limitation confirmed by multiple developers.
                // Reference: https://stackoverflow.com/questions/71555582
                visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    let isActive = self.view.window?.level.rawValue ?? 0 > 0
                    if self.wasVisibleInPopup && !isActive {
                        self.wasVisibleInPopup = false
                        self.player?.pause()
                    } else if !self.wasVisibleInPopup && isActive {
                        self.wasVisibleInPopup = true
                        self.player?.play()
                    }
                }
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        player?.pause()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        player?.pause()
        player = nil
        playerView.player = nil
    }

    func preparePreviewOfFile(at url: URL) async throws {
        do {
            let reader = try SVPReader(url: url)
            try reader.validateSVP()

            let mediaInfo = try reader.locatePrimaryMediaAsset()

            guard mediaInfo.likelyPlayableByAVFoundation else {
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

            let avAsset = AVURLAsset(url: mediaURL)
            let playerItem = AVPlayerItem(asset: avAsset)
            let avPlayer = AVPlayer(playerItem: playerItem)

            self.player = avPlayer
            self.playerView.player = avPlayer

            // Refine preferredContentSize with actual video dimensions.
            // loadView() sets a 16:9 default so Quick Look sizes the window early;
            // this corrects the aspect ratio for non-16:9 videos.
            if let videoTrack = try await avAsset.loadTracks(withMediaType: .video).first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
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
            }
        } catch let error as SVPError {
            showError(String(describing: error))
        } catch {
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
}
