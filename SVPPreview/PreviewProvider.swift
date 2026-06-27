import AVFoundation
import AVKit
import Cocoa
import Quartz
import SVPReader

@objc(PreviewProvider)
final class PreviewProvider: NSViewController, QLPreviewingController {
    private let containerView = SVPPreviewContainerView()
    private let playerView = AVPlayerView()
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var resourceLoader: SVPMediaResourceLoader?
    private let resourceLoaderQueue = DispatchQueue(label: "com.cueit.svp-system-support.preview.resource-loader")
    private var hasAutoPlayed = false
    private var visibilityTimer: Timer?
    private var wasVisibleInPopup = false

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func loadView() {
        containerView.frame = NSRect(x: 0, y: 0, width: 640, height: 360)

        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        containerView.playerView = playerView

        view = containerView
        preferredContentSize = Self.previewSize(forAspectRatio: 16.0 / 9.0)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        title = url.deletingPathExtension().lastPathComponent

        let asset: AVURLAsset
        do {
            let reader = try SVPReader(url: url)
            try reader.validateSVP()
            let mediaInfo = try reader.locatePrimaryMediaAsset()

            guard !mediaInfo.isCompressed else {
                throw SVPError.unsupportedCodec("Quick Look preview requires stored primary media for byte-range playback")
            }

            let loader = SVPMediaResourceLoader(reader: reader, mediaInfo: mediaInfo)
            let mediaURL = Self.previewMediaURL(for: mediaInfo)
            asset = AVURLAsset(url: mediaURL)
            asset.resourceLoader.setDelegate(loader, queue: resourceLoaderQueue)
            resourceLoader = loader
        } catch {
            handler(error)
            return
        }

        let item = AVPlayerItem(asset: asset)

        let player = AVPlayer(playerItem: item)
        playerView.player = player

        self.playerItem = item
        self.player = player
        updatePlayerAspectRatio(from: asset)

        handler(nil)
        autoPlayIfNeeded(reason: "preview-ready")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateControlsStyleForWindowContext(reason: "viewDidAppear")
        autoPlayIfNeeded(reason: "viewDidAppear")
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        pausePreviewPlayback(reason: "viewWillDisappear")
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        tearDownPreviewPlayback(reason: "viewDidDisappear")
    }

    private func updatePlayerAspectRatio(from asset: AVURLAsset) {
        Task { [weak self] in
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let displaySize = CGSize(
                    width: abs(transform.a) * naturalSize.width + abs(transform.c) * naturalSize.height,
                    height: abs(transform.b) * naturalSize.width + abs(transform.d) * naturalSize.height
                )
                guard displaySize.width > 0, displaySize.height > 0 else { return }

                let aspectRatio = displaySize.width / displaySize.height
                await MainActor.run {
                    self?.setPlayerAspectRatio(aspectRatio)
                }
            } catch {
                return
            }
        }
    }

    private func setPlayerAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0 else { return }
        containerView.aspectRatio = aspectRatio
    }

    private func autoPlayIfNeeded(reason: String) {
        updateControlsStyleForWindowContext(reason: reason)

        guard !hasAutoPlayed, let window = view.window, window.level.rawValue > 0 else { return }

        hasAutoPlayed = true
        wasVisibleInPopup = true
        player?.play()
        startVisibilityTimer()
    }

    private func startVisibilityTimer() {
        visibilityTimer?.invalidate()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }

            let isVisibleInPopup = self.view.window?.level.rawValue ?? 0 > 0
            self.updateControlsStyleForWindowContext(reason: "visibilityTimer")
            if self.wasVisibleInPopup && !isVisibleInPopup {
                self.wasVisibleInPopup = false
                self.pausePreviewPlayback(reason: "visibilityTimer-hidden")
            } else if !self.wasVisibleInPopup && isVisibleInPopup {
                self.wasVisibleInPopup = true
                self.player?.play()
            }
        }
    }

    private func updateControlsStyleForWindowContext(reason: String) {
        let isQuickLookPopup = view.window?.level.rawValue ?? 0 > 0
        let controlsStyle: AVPlayerViewControlsStyle = isQuickLookPopup ? .floating : .inline
        guard playerView.controlsStyle != controlsStyle else { return }

        playerView.controlsStyle = controlsStyle
    }

    private func pausePreviewPlayback(reason: String) {
        player?.pause()
    }

    private func tearDownPreviewPlayback(reason: String) {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        pausePreviewPlayback(reason: reason)
        player?.replaceCurrentItem(with: nil)
        playerView.player = nil
        playerItem = nil
        player = nil
        resourceLoader = nil
    }

    private static func previewMediaURL(for mediaInfo: SVPMediaInfo) -> URL {
        var components = URLComponents()
        components.scheme = "svp-preview-media"
        components.host = "primary"
        components.path = "/" + mediaInfo.mediaFileName
        return components.url!
    }

    private static func previewSize(forAspectRatio aspectRatio: CGFloat) -> CGSize {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let margin: CGFloat = 120
        let maxWidth = max(640, screenFrame.width - margin)
        let maxHeight = max(360, screenFrame.height - margin)

        if maxWidth / maxHeight > aspectRatio {
            let height = maxHeight
            return CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = maxWidth
            return CGSize(width: width, height: width / aspectRatio)
        }
    }

    deinit {
        tearDownPreviewPlayback(reason: "deinit")
    }
}

private final class SVPPreviewContainerView: NSView {
    var aspectRatio: CGFloat = 16.0 / 9.0 {
        didSet {
            needsLayout = true
        }
    }

    var playerView: AVPlayerView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let playerView {
                addSubview(playerView)
                needsLayout = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        guard let playerView, bounds.width > 0, bounds.height > 0, aspectRatio > 0 else { return }

        let fittedSize: CGSize
        if bounds.width / bounds.height > aspectRatio {
            let height = bounds.height
            fittedSize = CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = bounds.width
            fittedSize = CGSize(width: width, height: width / aspectRatio)
        }

        playerView.frame = NSRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        ).integral
    }
}
