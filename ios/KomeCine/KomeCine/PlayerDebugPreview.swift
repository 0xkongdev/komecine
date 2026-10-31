import Foundation

/// Preview runs use a separate local store and never authenticate cloud synchronization.
enum PlayerDebugEnvironment {
    static var enabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KOMECINE_PLAYER_PREVIEW"] == "1"
        #else
        return false
        #endif
    }
    static var defaults: UserDefaults {
        enabled ? UserDefaults(suiteName:"app.komecine.player-preview")! : .standard
    }
}

#if DEBUG
import Foundation

/// A deterministic local video for previews and UI automation, never enabled in release builds.
@MainActor enum PlayerDebugPreview {
    static func openIfRequested(_ playback: PlaybackCoordinator) {
        guard PlayerDebugEnvironment.enabled,
              let url = Bundle.main.url(forResource:"player-preview",withExtension:"mp4") else { return }
        let movie = Movie(id:"preview:player",slug:"preview-player",name:"KomeCine · Player",originName:"",posterURL:nil,backdropURL:nil,year:2026)
        let sources = (1...4).map { PlaybackSource(server:"Nguồn thử",name:"Tập \($0)",slug:"\($0)",url:url.absoluteString) }
        playback.open(movie:movie,source:sources[0],sources:sources,description:"Bản xem trước để kiểm tra giao diện và thao tác của player.")
        playback.pause()
    }
}
#endif
