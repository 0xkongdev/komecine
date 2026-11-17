import Foundation

/// Preview runs use a separate local store and never authenticate cloud synchronization.
enum PlayerDebugEnvironment {
    static var enabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KOMECINE_PLAYER_PREVIEW"] == "1"
            || ProcessInfo.processInfo.environment["KOMECINE_LIBRARY_PREVIEW"] == "1"
        #else
        return false
        #endif
    }
    static var defaults: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KOMECINE_LIBRARY_PREVIEW"] == "1" {
            return UserDefaults(suiteName:"app.komecine.library-preview")!
        }
        #endif
        return enabled ? UserDefaults(suiteName:"app.komecine.player-preview")! : .standard
    }
}

#if DEBUG
import Foundation

/// A deterministic local video for previews and UI automation, never enabled in release builds.
@MainActor enum PlayerDebugPreview {
    static func openIfRequested(_ playback: PlaybackCoordinator) {
        guard ProcessInfo.processInfo.environment["KOMECINE_PLAYER_PREVIEW"] == "1",
              let url = Bundle.main.url(forResource:"player-preview",withExtension:"mp4") else { return }
        let movie = Movie(id:"preview:player",slug:"preview-player",name:"KomeCine · Player",originName:"",posterURL:nil,backdropURL:nil,year:2026)
        let sources = (1...4).map { PlaybackSource(server:"Nguồn thử",name:"Tập \($0)",slug:"\($0)",url:url.absoluteString) }
        playback.open(movie:movie,source:sources[0],sources:sources,description:"Bản xem trước để kiểm tra giao diện và thao tác của player.")
        playback.pause()
    }
}

/// Wide artwork reproduces overlapping hit regions without network or account data.
@MainActor enum LibraryDebugPreview {
    static func prepareIfRequested(_ library: LocalLibrary) async {
        guard ProcessInfo.processInfo.environment["KOMECINE_LIBRARY_PREVIEW"] == "1" else { return }
        let source = PlaybackSource(server:"Preview",name:"Tập 1",slug:"1",url:"")
        for index in (1...3).reversed() {
            let url = "https://library-preview.invalid/\(index).png"
            await PosterImageLoader.shared.prepareLibraryPreviewImage(url: url)
            let movie = Movie(id:"library-preview-\(index)",slug:"library-preview-\(index)",
                              name:"Phim thử \(index)",originName:"",posterURL:url,backdropURL:nil,year:2026)
            library.record(movie,source:source,position:30,duration:300)
        }
    }
}
#endif
