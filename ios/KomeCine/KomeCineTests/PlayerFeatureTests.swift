import Foundation
import Testing
import AVFoundation
@testable import KomeCine

struct PlayerFeatureTests {
    @MainActor @Test func expandingDuringDismissalWaitsForPresentationToFinish() {
        let playback = PlaybackCoordinator()
        let movie = Movie(id:"transition",slug:"transition",name:"Movie",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let source = PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        playback.open(movie:movie,source:source,sources:[source])
        playback.minimize()
        playback.expand()
        #expect(!playback.isExpanded)
        playback.presentationDidDismiss()
        #expect(playback.isExpanded)
        playback.stop()
    }

    @MainActor @Test func oldLibraryCannotEnqueueProgressForNewAuthentication() throws {
        let defaults = UserDefaults(suiteName:UUID().uuidString)!
        let library = LocalLibrary(defaults:defaults)
        library.setAccount("alice")
        let movie = Movie(id:"alice-movie",slug:"movie",name:"Movie",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let source = PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        library.record(movie,source:source,position:42,duration:100)
        var authenticatedAccount = "alice"
        let sync = CloudSync(defaults:defaults, credentials:{ (authenticatedAccount,"unit-token") })
        sync.configure(library:library,auth:nil)
        sync.saveProgressNow()
        #expect(defaults.data(forKey:"sync.pending.alice") != nil)
        authenticatedAccount = "bob"
        sync.saveProgressNow() // Called by stop() before LocalLibrary switches account.
        #expect(defaults.data(forKey:"sync.pending.bob") == nil)
        library.setAccount("bob")
        sync.saveProgressNow()
        #expect(defaults.data(forKey:"sync.pending.bob") == nil)
    }

    @MainActor @Test func subtitleFailureIsReportedOnceUntilUserRetries() async throws {
        var attempts = 0
        var failures = 0
        let controller = SubtitleController(resource:{ _ in attempts += 1; throw URLError(.cannotConnectToHost) })
        controller.onFailure = { _ in failures += 1 }
        controller.select(primary:HLSTextTrack(name:"Vietnamese",language:"vi",url:URL(string:"https://example.com/sub.m3u8")!),secondary:nil)
        for _ in 0..<100 { if controller.error != nil { break }; try await Task.sleep(for:.milliseconds(10)) }
        #expect(controller.error != nil)
        for clock in 1...5 { controller.update(time:Double(clock)); await Task.yield() }
        #expect(attempts == 1)
        #expect(failures == 1)
    }

    @Test func wrappedMPEGTimestampAlignsToSameVideoTimeline() {
        let first = "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:8589844592\n\n00:00:00.000 --> 00:00:02.000\nFirst"
        let next = "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:06.000,MPEGTS:450000\n\n00:00:06.000 --> 00:00:08.000\nNext"
        let origin = WebVTT.mapOffset(first)!
        let cues = WebVTT.aligned(next,origin:origin)
        #expect(abs((cues.first?.start ?? -1) - 6) < 0.001)
        #expect(WebVTT.text(at:7,cues:cues) == "Next")
    }

    @MainActor @Test func newerCloudProgressWinsForPreviouslyWatchedEpisode() {
        let library = LocalLibrary(defaults:UserDefaults(suiteName:UUID().uuidString)!)
        let movie = Movie(id:"movie",slug:"movie",name:"Movie",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let source = PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        library.record(movie,source:source,position:42,duration:400)
        let remote = WatchProgress(movieId:"movie",episodeSlug:"1",server:"S",position:300,duration:400,updatedAt:Int64(Date().timeIntervalSince1970 * 1000) + 10_000)
        library.applyCloud(favorites:[],progress:[remote],movies:[movie.id:movie])
        #expect(library.episodeProgress(movieID:"movie",source:source)?.position == 300)
    }

    @Test func repeatedSegmentBoundaryCuesAreShownOnce() {
        let cue = SubtitleCue(start:5,end:7,text:"Boundary cue")
        #expect(WebVTT.text(at:6,cues:[cue,cue]) == "Boundary cue")
    }

    @MainActor @Test func nativePauseDoesNotResumeWhenChangingSpeed() async throws {
        let url = try #require(Bundle.main.url(forResource:"player-preview",withExtension:"mp4"))
        let playback = PlaybackCoordinator()
        let movie = Movie(id:"native-test",slug:"native-test",name:"Movie",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let source = PlaybackSource(server:"S",name:"1",slug:"1",url:url.absoluteString)
        playback.open(movie:movie,source:source,sources:[source])
        defer { playback.stop() }
        for _ in 0..<300 {
            if playback.isPlaying { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        #expect(playback.isPlaying)
        playback.player?.pause() // PiP and system controls act directly on AVPlayer.
        try await Task.sleep(for:.milliseconds(100))
        #expect(!playback.isPlaying)
        playback.setSpeed(1.5)
        #expect(playback.player?.rate == 0)
        playback.togglePlayback()
        #expect(playback.player?.rate == 1.5)
    }

    @MainActor @Test func downloadsMigrateGuestOnceAndFilterOldOwnerCallbacks() {
        let defaults = UserDefaults(suiteName:UUID().uuidString)!
        let manager = OfflineDownloads(defaults:defaults)
        let movie = Movie(id:"movie",slug:"movie",name:"Movie",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let source = PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        let record = DownloadRecord(movie:movie, source:source, owner:"guest")
        manager.store(record)
        manager.setAccount("alice")
        #expect(manager.records.count == 1)
        manager.setAccount("bob")
        #expect(manager.records.isEmpty)
        manager.updateProgress(id:record.id, fraction:2)
        #expect(manager.records.isEmpty)
        manager.setAccount("alice")
        #expect(manager.records.first?.progress == 1)
        manager.updateProgress(id:record.id, fraction:0.2)
        #expect(manager.records.first?.progress == 1)
        #expect(manager.localURL(movie:movie, source:source) == nil)
        let restored = OfflineDownloads(defaults:defaults)
        restored.setAccount("alice")
        #expect(restored.records.first?.id == record.id)
        restored.setAccount(nil)
        #expect(restored.records.isEmpty)
    }

    @MainActor @Test func perEpisodeHistorySurvivesWatchingAnotherEpisodeAndAccountChanges() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let library = LocalLibrary(defaults: defaults)
        let movie = Movie(id:"movie",slug:"movie",name:"Movie",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let one = PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        let two = PlaybackSource(server:"S",name:"2",slug:"2",url:"https://example.com/2.m3u8")
        library.record(movie, source:one, position:42, duration:100)
        library.record(movie, source:two, position:12, duration:100)
        #expect(library.episodeProgress(movieID:"movie", source:one)?.position == 42)
        #expect(library.progress["movie"]?.episodeSlug == "2")
        library.setAccount("alice")
        #expect(library.episodeProgress(movieID:"movie", source:one)?.position == 42)
        library.setAccount("bob")
        #expect(library.episodeProgress(movieID:"movie", source:one) == nil)
        library.setAccount("alice")
        #expect(library.episodeProgress(movieID:"movie", source:two)?.position == 12)
    }

    @MainActor @Test func temporaryBoostRestoresChosenSpeedAndRejectsInvalidSpeed() {
        let playback = PlaybackCoordinator()
        playback.setSpeed(1.5)
        playback.beginBoost()
        #expect(playback.effectiveSpeed == 2)
        #expect(playback.selectedSpeed == 1.5)
        playback.endBoost()
        #expect(playback.effectiveSpeed == 1.5)
        playback.setSpeed(-1)
        #expect(playback.selectedSpeed == 1.5)
        playback.setSpeed(.infinity)
        #expect(playback.selectedSpeed == 1.5)
    }

    @Test func seekingRejectsInvalidTimelinesAndClampsToVideo() {
        #expect(PlaybackMath.clamp(-10, duration: 100) == 0)
        #expect(PlaybackMath.clamp(150, duration: 100) == 100)
        #expect(PlaybackMath.clamp(25, duration: .infinity) == nil)
        #expect(PlaybackMath.clamp(.nan, duration: 100) == nil)
        #expect(PlaybackMath.clamp(25, duration: 0) == nil)
    }

    @Test func lockingClosesPanelsAndInteractionProtectsControls() {
        var state = PlayerInteractionState()
        state.open(.speed)
        state.autoHide(isPlaying: true, voiceOver: false)
        #expect(state.visible)
        state.toggleLock()
        #expect(state.panel == nil)
        #expect(state.locked)
        state.open(.episodes)
        #expect(state.panel == nil)
        state.autoHide(isPlaying: true, voiceOver: false)
        #expect(!state.visible)
        state.reveal()
        state.toggleLock()
        state.autoHide(isPlaying: false, voiceOver: false)
        #expect(state.visible)
    }

    @Test func hlsResolvesRelativeVariantsAndQuotedTrackNames() throws {
        let manifest = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Vietnamese, CC",LANGUAGE="vi",URI="sub/vi.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,SUBTITLES="subs"
        720/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1920x1080
        /1080.m3u8
        """
        let metadata = HLSMetadata.parse(manifest, baseURL: URL(string: "https://example.com/movie/master.m3u8")!)
        #expect(metadata.qualities.map(\.height) == [1080, 720])
        #expect(metadata.qualities.last?.url.absoluteString == "https://example.com/movie/720/index.m3u8")
        #expect(metadata.subtitles.first?.name == "Vietnamese, CC")
        #expect(metadata.subtitles.first?.url.absoluteString == "https://example.com/movie/sub/vi.m3u8")
        #expect(HLSMetadata.parse("#EXTM3U\n#EXTINF:6\na.ts", baseURL: URL(string:"https://example.com/a.m3u8")!).qualities.isEmpty)
    }

    @Test func webVTTCuesAlignWithTimestampMapAndIgnoreMarkup() {
        let text = """
        WEBVTT
        X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:900000

        cue-1
        00:00:01.000 --> 00:00:03.000 align:center
        <v Narrator>Xin <b>chào</b> &amp; bạn

        00:00:04.000 --> 00:00:05.000
        Tạm biệt
        """
        let cues = WebVTT.parse(text, segmentStart: 10)
        #expect(cues.count == 2)
        #expect(cues.first?.start == 11)
        #expect(cues.first?.end == 13)
        #expect(cues.first?.text == "Xin chào & bạn")
        #expect(WebVTT.text(at: 12, cues: cues) == "Xin chào & bạn")
        #expect(WebVTT.text(at: 13, cues: cues).isEmpty)
    }
}
