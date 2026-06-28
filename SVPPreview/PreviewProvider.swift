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
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var playerLikelyToKeepUpObservation: NSKeyValueObservation?
    private var playbackDiagnosticsTimer: Timer?

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
            log("prepare url=\(url.path) media=\(mediaInfo.mediaFileName) bytes=\(mediaInfo.uncompressedSize)")
        } catch {
            log("prepare-error url=\(url.path) error=\(error)")
            handler(error)
            return
        }

        let item = AVPlayerItem(asset: asset)

        let player = AVPlayer(playerItem: item)
        playerView.player = player

        self.playerItem = item
        self.player = player
        startPlaybackDiagnostics(player: player, item: item)
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
        log("play reason=\(reason)")
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
                self.log("play reason=visibilityTimer-visible")
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
        log("pause reason=\(reason)")
        player?.pause()
    }

    private func tearDownPreviewPlayback(reason: String) {
        log("teardown reason=\(reason)")
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        playbackDiagnosticsTimer?.invalidate()
        playbackDiagnosticsTimer = nil
        playerItemStatusObservation = nil
        playerTimeControlObservation = nil
        playerLikelyToKeepUpObservation = nil
        NotificationCenter.default.removeObserver(self)
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

    private func startPlaybackDiagnostics(player: AVPlayer, item: AVPlayerItem) {
        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            guard let self, let item else { return }
            self.log(
                "item-status status=\(Self.itemStatusDescription(item.status)) likelyToKeepUp=\(item.isPlaybackLikelyToKeepUp) loaded=\(Self.loadedRangesDescription(item.loadedTimeRanges)) error=\(String(describing: item.error))"
            )
        }

        playerLikelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self, weak item] _, _ in
            guard let self, let item else { return }
            self.log(
                "item-keep-up likelyToKeepUp=\(item.isPlaybackLikelyToKeepUp) loaded=\(Self.loadedRangesDescription(item.loadedTimeRanges))"
            )
        }

        playerTimeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak player] _, _ in
            guard let self, let player else { return }
            self.log(
                "player-time-control status=\(Self.timeControlStatusDescription(player.timeControlStatus)) reason=\(String(describing: player.reasonForWaitingToPlay)) rate=\(player.rate)"
            )
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemPlaybackStalled(_:)),
            name: .AVPlayerItemPlaybackStalled,
            object: item
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEnd(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemNewAccessLog(_:)),
            name: .AVPlayerItemNewAccessLogEntry,
            object: item
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemNewErrorLog(_:)),
            name: .AVPlayerItemNewErrorLogEntry,
            object: item
        )

        playbackDiagnosticsTimer?.invalidate()
        playbackDiagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self, weak player, weak item] _ in
            guard let self, let player, let item else { return }
            self.log(
                "heartbeat time=\(Self.formatTime(player.currentTime())) rate=\(player.rate) status=\(Self.timeControlStatusDescription(player.timeControlStatus)) likelyToKeepUp=\(item.isPlaybackLikelyToKeepUp) loaded=\(Self.loadedRangesDescription(item.loadedTimeRanges)) reason=\(String(describing: player.reasonForWaitingToPlay))"
            )
        }
    }

    @objc private func playerItemPlaybackStalled(_ notification: Notification) {
        log("notification playback-stalled")
    }

    @objc private func playerItemFailedToPlayToEnd(_ notification: Notification) {
        log("notification failed-to-play-to-end userInfo=\(notification.userInfo ?? [:])")
    }

    @objc private func playerItemNewAccessLog(_ notification: Notification) {
        guard let event = playerItem?.accessLog()?.events.last else {
            log("access-log empty")
            return
        }

        log(
            "access-log observedBitrate=\(event.observedBitrate) indicatedBitrate=\(event.indicatedBitrate) stalls=\(event.numberOfStalls) transferDuration=\(event.transferDuration) uri=\(event.uri ?? "nil")"
        )
    }

    @objc private func playerItemNewErrorLog(_ notification: Notification) {
        guard let event = playerItem?.errorLog()?.events.last else {
            log("error-log empty")
            return
        }

        log(
            "error-log status=\(event.errorStatusCode) domain=\(event.errorDomain) comment=\(event.errorComment ?? "nil")"
        )
    }

    private func log(_ message: String) {
        fputs("SVPQL \(Date()) preview \(message)\n", stderr)
        fflush(stderr)
    }

    private static func itemStatusDescription(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "unknown-default"
        }
    }

    private static func timeControlStatusDescription(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case .playing: return "playing"
        @unknown default: return "unknown-default"
        }
    }

    private static func loadedRangesDescription(_ ranges: [NSValue]) -> String {
        ranges.map { value in
            let range = value.timeRangeValue
            return "\(formatTime(range.start))+\(formatTime(range.duration))"
        }.joined(separator: ",")
    }

    private static func formatTime(_ time: CMTime) -> String {
        guard time.isNumeric else { return "nan" }
        return String(format: "%.3f", CMTimeGetSeconds(time))
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
