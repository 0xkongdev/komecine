import Foundation
import Testing
@testable import KomeCine

struct PlayerFeatureTests {
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
