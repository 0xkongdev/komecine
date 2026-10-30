import Foundation
import Combine
import AVKit

struct PlayerMediaTrack: Identifiable {
    let id: String
    let name: String
    let language: String
    let option: AVMediaSelectionOption?
    let external: HLSTextTrack?
}

@MainActor final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var movie: Movie?
    @Published private(set) var source: PlaybackSource?
    @Published private(set) var sources: [PlaybackSource] = []
    @Published private(set) var player: AVPlayer?
    @Published var isExpanded = false
    @Published private(set) var countdown = 0
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var buffered = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = true
    @Published private(set) var error: String?
    @Published private(set) var selectedSpeed: Float = 1
    @Published private(set) var boosted = false
    @Published private(set) var qualities: [VideoQuality] = []
    @Published private(set) var selectedQuality: Int?
    @Published private(set) var audioTracks: [PlayerMediaTrack] = []
    @Published private(set) var captionTracks: [PlayerMediaTrack] = []
    @Published private(set) var audioID: String?
    @Published private(set) var captionID: String?
    @Published private(set) var secondaryCaptionID: String?
    @Published private(set) var metadataLoading = false
    @Published private(set) var usingOfflineAsset = false
    @Published var captionSize: Double = 20 { didSet { applyCaptionStyle() } }
    @Published var isInPiP = false { didSet { syncCaptions() } }
    @Published private(set) var isExternalPlayback = false
    @Published var introSkipSeconds = 0.0 {
        didSet { if let movie { UserDefaults.standard.set(introSkipSeconds, forKey:"player.intro.\(movie.id)") } }
    }
    var movieDescription = ""
    let subtitles = SubtitleController()
    var offlineURL: ((Movie, PlaybackSource) -> URL?)?
    private weak var library: LocalLibrary?
    private weak var sync: CloudSync?
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var nextTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var token = UUID()
    private var lastSaved = Date.distantPast
    private var wantsToPlay = false
    private var wasPlayingBeforeBoost = false
    private var audioGroup: AVMediaSelectionGroup?
    private var captionGroup: AVMediaSelectionGroup?
    private var pendingResume: Double?
    private var imageOutput: AVPlayerItemVideoOutput?
    static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3]
    var effectiveSpeed: Float { boosted ? 2 : selectedSpeed }
    var nextSource: PlaybackSource? { source?.next(in:sources) }

    func configure(library: LocalLibrary, sync: CloudSync) { self.library = library; self.sync = sync }
    func open(movie: Movie, source: PlaybackSource, sources: [PlaybackSource], description: String = "") {
        if self.movie?.id == movie.id, self.source?.id == source.id, player != nil { isExpanded = true; return }
        cancelNext(); finishItem()
        self.movie = movie; self.source = source; self.sources = sources; movieDescription = description
        introSkipSeconds = UserDefaults.standard.double(forKey:"player.intro.\(movie.id)")
        start(source, resume: savedPosition(movie:movie, source:source)); isExpanded = true
    }
    func minimize() { endBoost(); save(); sync?.saveProgressNow(); isExpanded = false }
    func expand() { if player != nil { isExpanded = true } }
    func change(to next: PlaybackSource) {
        guard let movie else { return }
        let resume = source?.slug == next.slug ? position : savedPosition(movie:movie, source:next)
        cancelNext(); finishItem(); source = next; start(next, resume:resume)
    }
    func changeServer(to server: String) {
        guard let next = sources.first(where: { $0.server == server && $0.slug == source?.slug }) ?? sources.first(where: { $0.server == server }) else { return }
        change(to:next)
    }
    func retry() {
        guard let source else { return }
        let resume = position; finishItem(); start(source, resume:resume)
    }
    func cancelNext() { nextTask?.cancel(); nextTask = nil; countdown = 0 }
    func stop() {
        endBoost(); cancelNext(); finishItem(); sync?.saveProgressNow()
        player?.pause(); player = nil; isExpanded = false; movie = nil; source = nil; sources = []
        isPlaying = false; wantsToPlay = false; position = 0; duration = 0; error = nil
    }
    func play() { wantsToPlay = true; player?.playImmediately(atRate:effectiveSpeed) }
    func pause() { wantsToPlay = false; player?.pause(); isPlaying = false }
    func togglePlayback() { wantsToPlay ? pause() : play() }
    func setSpeed(_ value: Float) {
        guard Self.speeds.contains(value) else { return }
        selectedSpeed = value
        if wantsToPlay { player?.playImmediately(atRate:effectiveSpeed) }
    }
    func beginBoost() {
        guard !boosted else { return }
        wasPlayingBeforeBoost = wantsToPlay; boosted = true
        if player != nil { play() }
    }
    func endBoost() {
        guard boosted else { return }
        boosted = false
        if wasPlayingBeforeBoost { play() } else { pause() }
    }
    func seek(to seconds: Double) {
        guard let value = PlaybackMath.clamp(seconds, duration:duration), let player else { return }
        cancelNext(); position = value
        player.seek(to:CMTime(seconds:value, preferredTimescale:600), toleranceBefore:.zero, toleranceAfter:.zero)
        subtitles.update(time:value)
    }
    func skip(_ delta: Double) { seek(to:position + delta) }
    func selectQuality(_ height: Int?) {
        guard height == nil || qualities.contains(where: { $0.height == height }) else { return }
        selectedQuality = height
        if let choice = qualities.first(where: { $0.height == height }) {
            player?.currentItem?.preferredMaximumResolution = CGSize(width:choice.width, height:choice.height)
        } else { player?.currentItem?.preferredMaximumResolution = .zero }
    }
    func selectAudio(_ id: String) {
        guard let group = audioGroup, let track = audioTracks.first(where: { $0.id == id }), let option = track.option else { return }
        audioID = id; player?.currentItem?.select(option, in:group)
    }
    func selectCaption(_ id: String?) {
        captionID = id
        if secondaryCaptionID == id { secondaryCaptionID = nil }
        syncCaptions()
    }
    func selectSecondaryCaption(_ id: String?) { secondaryCaptionID = id == captionID ? nil : id; syncCaptions() }
    func captureFrame() async throws -> UIImage {
        guard let item = player?.currentItem else { throw URLError(.resourceUnavailable) }
        if let buffer = imageOutput?.copyPixelBuffer(forItemTime:item.currentTime(), itemTimeForDisplay:nil) {
            let context = CIContext()
            let image = CIImage(cvPixelBuffer:buffer)
            if let cgImage = context.createCGImage(image, from:image.extent) { return UIImage(cgImage:cgImage) }
        }
        let generator = AVAssetImageGenerator(asset:item.asset)
        generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at:item.currentTime()).image
        return UIImage(cgImage:image)
    }
    private func savedPosition(movie: Movie, source: PlaybackSource) -> Double {
        guard let progress = library?.episodeProgress(movieID:movie.id, source:source),
              progress.position > 0, progress.duration <= 0 || progress.position < progress.duration - 1 else { return 0 }
        return progress.position
    }
    private func start(_ source: PlaybackSource, resume: Double) {
        guard let remote = URL(string:source.url), ["http", "https", "file"].contains(remote.scheme?.lowercased() ?? "") else { error = "Nguồn phát không hợp lệ."; return }
        let local = movie.flatMap { offlineURL?($0, source) }
        let url = local ?? remote; usingOfflineAsset = local != nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode:.moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        position = resume; duration = 0; buffered = 0; error = nil; isBuffering = true
        qualities = []; selectedQuality = nil; audioTracks = []; captionTracks = []; audioID = nil; captionID = nil; secondaryCaptionID = nil
        audioGroup = nil; captionGroup = nil; pendingResume = resume > 0 ? resume : nil
        let item = AVPlayerItem(url:url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        item.add(output); imageOutput = output
        let p = player ?? AVPlayer(); player = p; p.replaceCurrentItem(with:item)
        let session = token
        observations = [
            item.observe(\.status, options:[.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.token == session, self.player?.currentItem === item else { return }
                    if item.status == .failed { self.error = "Không phát được video. Hãy thử lại hoặc chọn server khác."; self.isBuffering = false; self.isPlaying = false }
                    if item.status == .readyToPlay { self.refreshClock(); self.applyResume() }
                }
            },
            p.observe(\.timeControlStatus, options:[.initial, .new]) { [weak self] p, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.token == session else { return }
                    self.isPlaying = p.timeControlStatus == .playing
                    self.isBuffering = p.timeControlStatus == .waitingToPlayAtSpecifiedRate && self.error == nil
                }
            },
            p.observe(\.isExternalPlaybackActive, options:[.initial, .new]) { [weak self] p, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.token == session, self.isExternalPlayback != p.isExternalPlaybackActive else { return }
                    self.isExternalPlayback = p.isExternalPlaybackActive; self.syncCaptions()
                }
            }
        ]
        timeObserver = p.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.25, preferredTimescale:600), queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.token == session else { return }
                self.refreshClock(); self.applyResume(); self.subtitles.update(time:self.position)
                if Date().timeIntervalSince(self.lastSaved) >= 5 { self.save(); self.lastSaved = Date() }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime, object:item, queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, self.token == session else { return }; self.isPlaying = false; self.scheduleNext() }
        }
        metadataLoading = true
        metadataTask = Task { [weak self] in
            let metadata = url.isFileURL ? HLSMetadata() : (try? await HLSMetadata.load(url)) ?? HLSMetadata()
            let audible = try? await item.asset.loadMediaSelectionGroup(for:.audible)
            let legible = try? await item.asset.loadMediaSelectionGroup(for:.legible)
            guard let self, !Task.isCancelled, self.token == session else { return }
            self.qualities = metadata.qualities; self.audioGroup = audible; self.captionGroup = legible
            self.audioTracks = (audible?.options ?? []).enumerated().map { PlayerMediaTrack(id:"audio-\($0.offset)", name:$0.element.displayName, language:$0.element.extendedLanguageTag ?? "", option:$0.element, external:nil) }
            self.captionTracks = (legible?.options ?? []).enumerated().map { PlayerMediaTrack(id:"caption-\($0.offset)", name:$0.element.displayName, language:$0.element.extendedLanguageTag ?? "", option:$0.element, external:nil) }
            for track in metadata.subtitles {
                if let index = self.captionTracks.firstIndex(where: { !$0.language.isEmpty && $0.language == track.language }) {
                    let old = self.captionTracks[index]
                    self.captionTracks[index] = PlayerMediaTrack(id:old.id, name:old.name, language:old.language, option:old.option, external:track)
                } else { self.captionTracks.append(PlayerMediaTrack(id:track.id, name:track.name, language:track.language, option:nil, external:track)) }
            }
            if let group = audible, let selected = item.currentMediaSelection.selectedMediaOption(in:group) { self.audioID = self.audioTracks.first(where: { $0.option == selected })?.id }
            if let group = legible, let selected = item.currentMediaSelection.selectedMediaOption(in:group) { self.captionID = self.captionTracks.first(where: { $0.option == selected })?.id }
            self.metadataLoading = false; self.applyCaptionStyle()
        }
        play()
    }
    private func refreshClock() {
        guard let item = player?.currentItem else { return }
        let time = item.currentTime().seconds, total = item.duration.seconds
        if pendingResume == nil, time.isFinite { position = max(0, time) }
        if total.isFinite, total > 0 { duration = total }
        buffered = item.loadedTimeRanges.compactMap { $0.timeRangeValue.end.seconds }.filter(\.isFinite).max() ?? 0
    }
    private func applyResume() {
        guard let resume = pendingResume, duration > 0 else { return }
        pendingResume = nil; seek(to:min(resume, max(0, duration - 0.1)))
    }
    private func syncCaptions() {
        let primary = captionTracks.first { $0.id == captionID }
        let secondary = captionTracks.first { $0.id == secondaryCaptionID }
        let externalPresentation = isInPiP || isExternalPlayback
        let renderCustom = primary?.external != nil && !externalPresentation
        if let group = captionGroup { player?.currentItem?.select(renderCustom ? nil : primary?.option, in:group) }
        subtitles.select(primary:renderCustom ? primary?.external : nil, secondary:renderCustom ? secondary?.external : nil)
        applyCaptionStyle()
    }
    private func applyCaptionStyle() {
        let attributes: [String: Any] = [kCMTextMarkupAttribute_RelativeFontSize as String:captionSize / 20 * 100]
        if let rule = AVTextStyleRule(textMarkupAttributes:attributes) { player?.currentItem?.textStyleRules = [rule] }
    }
    private func scheduleNext() {
        guard let next = nextSource else { return }
        cancelNext(); countdown = 5
        nextTask = Task { [weak self] in
            for value in (1...5).reversed() {
                guard !Task.isCancelled, let self else { return }; self.countdown = value
                do { try await Task.sleep(for:.seconds(1)) } catch { return }
            }
            guard !Task.isCancelled, let self else { return }; self.countdown = 0; self.change(to:next)
        }
    }
    private func save() {
        guard let movie, let source, player != nil, position.isFinite, duration.isFinite else { return }
        library?.record(movie, source:source, position:position, duration:duration)
    }
    private func finishItem() {
        save(); token = UUID(); metadataTask?.cancel(); metadataTask = nil; metadataLoading = false
        subtitles.select(primary:nil, secondary:nil)
        observations = []; if let timeObserver, let player { player.removeTimeObserver(timeObserver) }; timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
        player?.pause(); imageOutput = nil; pendingResume = nil
    }
}
