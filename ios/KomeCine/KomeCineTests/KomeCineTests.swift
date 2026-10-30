import Testing
import Foundation
@testable import KomeCine

@MainActor struct KomeCineTests {
    @Test func decodesMovieFromBackend() throws {
        let data = #"{"id":"kkphim:x","slug":"x","name":"Film","originName":"","posterURL":null,"backdropURL":null,"year":2024}"#.data(using: .utf8)!
        let movie = try JSONDecoder().decode(Movie.self, from: data)
        #expect(movie.id == "kkphim:x")
        #expect(movie.name == "Film")
        #expect(movie.posterURL == nil)
    }
    @Test func resumePositionRespectsBackwardSeek() {
        let earlier = WatchProgress(movieId: "x", episodeSlug: "1", server: "S", position: 80, duration: 100, updatedAt: 1)
        let later = WatchProgress(movieId: "x", episodeSlug: "1", server: "S", position: 20, duration: 100, updatedAt: 2)
        #expect(WatchProgress.mostRecent(earlier, later).position == 20)
    }
}

@MainActor struct SourceAdapterTests {
    @Test func resolvesCatalogPosterPathsFromCDNRoot() throws {
        let json = #"{"status":"success","data":{"APP_DOMAIN_CDN_IMAGE":"https://phimimg.com","items":[{"name":"Film","slug":"film","poster_url":"uploads/movies/20261022/film-poster.webp","thumb_url":"uploads/movies/20261022/film-thumb.webp"}]}}"#.data(using:.utf8)!
        let movie = try #require(KKPhimAdapter.decodePage(json).first)
        #expect(movie.posterURL == "https://phimimg.com/uploads/movies/20261022/film-poster.webp")
        #expect(movie.backdropURL == "https://phimimg.com/uploads/movies/20261022/film-thumb.webp")
        #expect(KKPhimAdapter.image("film.jpg", base:"https://phimimg.com/uploads/movies/") == "https://phimimg.com/uploads/movies/film.jpg")
        #expect(KKPhimAdapter.image("upload/vod/film.jpg", base:"https://phimimg.com/uploads/movies/") == "https://phimimg.com/upload/vod/film.jpg")
    }
    @Test func mapsKKPhimBadImageAndHLS() throws {
        let json = #"{"status":true,"movie":{"name":"Film","slug":"film","poster_url":{},"thumb_url":"a.jpg"},"episodes":[{"server_name":"Vietsub","server_data":[{"name":"1","slug":"tap-1","link_m3u8":"https://example.com/1.m3u8"},{"name":"2","slug":"tap-2","link_embed":"https://example.com"}]}]}"#.data(using:.utf8)!
        let detail = try KKPhimAdapter.decodeDetail(json)
        #expect(detail.posterURL == nil)
        #expect(detail.sources.count == 1)
        #expect(detail.sources[0].server == "Vietsub")
    }
}

@MainActor struct LocalLibraryTests {
    @Test func catalogArtworkAppliesToHistoryArrivingAfterHomeLoaded() {
        let library = LocalLibrary(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let movie = Movie(id:"kkphim:x",slug:"x",name:"Film",originName:"Original title",posterURL:nil,backdropURL:nil,year:2026)
        let catalog = Movie(id:"rophim:1",slug:"other",name:"Film",originName:"Original title",posterURL:"https://example.com/poster.jpg",backdropURL:nil,year:2026)
        let progress = WatchProgress(movieId:movie.id,episodeSlug:"1",server:"S",position:42,duration:100,updatedAt:1)
        library.updatePosterFallbacks(from:[catalog])
        library.applyCloud(favorites:[],progress:[progress],movies:[movie.id:movie])
        #expect(library.posterFallbacks[movie.id] == "https://example.com/poster.jpg")
        library.setAccount("another-account")
        library.toggleFavorite(movie)
        #expect(library.posterFallbacks[movie.id] == "https://example.com/poster.jpg")
    }

    @Test func matchesAndPersistsAlternateArtworkWithoutChangingWatchHistory() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let library = LocalLibrary(defaults: defaults)
        let movie = Movie(id:"kkphim:love",slug:"love",name:"Yêu một người khác",originName:"A Love Other Than Yours",posterURL:"https://slow.example/poster.webp",backdropURL:nil,year:2026)
        let source = PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        library.record(movie,source:source,position:42,duration:100)
        let otherYear = Movie(id:"rophim:old",slug:"old",name:"Same title",originName:"A Love Other Than Yours",posterURL:"https://example.com/wrong.jpg",backdropURL:nil,year:2025)
        let matching = Movie(id:"rophim:50384",slug:"other-slug",name:"Other display title",originName:"A Love Other than Yours",posterURL:nil,backdropURL:"https://example.com/correct.jpg",year:2026)
        library.updatePosterFallbacks(from:[otherYear])
        #expect(library.posterFallbacks.isEmpty)
        library.updatePosterFallbacks(from:[otherYear,matching])
        #expect(library.posterFallbacks[movie.id] == "https://example.com/correct.jpg")
        #expect(library.recent == [movie])
        #expect(library.progress[movie.id]?.position == 42)
        #expect(LocalLibrary(defaults:defaults).posterFallbacks[movie.id] == "https://example.com/correct.jpg")
        library.setAccount("alice")
        #expect(library.posterFallbacks[movie.id] == "https://example.com/correct.jpg")
        library.setAccount("bob")
        #expect(library.posterFallbacks.isEmpty)
    }

    @Test func favoritesCanBeAddedAndRemoved() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let library = LocalLibrary(defaults: defaults)
        let movie = Movie(id:"kkphim:x",slug:"x",name:"Film",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        library.toggleFavorite(movie)
        #expect(library.favorites.map(\.id) == [movie.id])
        library.toggleFavorite(movie)
        #expect(library.favorites.isEmpty)
    }
}

@MainActor struct AuthConfigurationTests {
    @Test func rejectsMissingOrNonHttpsBackend() {
        #expect(AuthConfiguration(values: [:]) == nil)
        #expect(AuthConfiguration(values: ["GoogleClientID":"ios", "GoogleServerClientID":"server", "BackendURL":"http://example.com"]) == nil)
    }
    @Test func acceptsHttpsConfiguration() {
        #expect(AuthConfiguration(values: ["GoogleClientID":"ios", "GoogleServerClientID":"server", "BackendURL":"https://api.example.com"]) != nil)
    }
}

@MainActor struct AccountLibraryTests {
    @Test func accountDataDoesNotLeakBetweenUsers() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let lib=LocalLibrary(defaults:defaults)
        let movie=Movie(id:"kkphim:x",slug:"x",name:"Film",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        lib.setAccount("alice")
        lib.toggleFavorite(movie)
        lib.setAccount("bob")
        #expect(lib.favorites.isEmpty)
        lib.setAccount("alice")
        #expect(lib.favorites.map(\.id) == [movie.id])
    }
}

@MainActor struct EpisodeSequenceTests {
    @Test func nextEpisodeStaysOnCurrentServer() {
        let first=PlaybackSource(server:"Vietsub",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        let second=PlaybackSource(server:"Vietsub",name:"2",slug:"2",url:"https://example.com/2.m3u8")
        let other=PlaybackSource(server:"Lồng tiếng",name:"1",slug:"1",url:"https://example.com/3.m3u8")
        #expect(first.next(in:[first,second,other]) == second)
        #expect(second.next(in:[first,second,other]) == nil)
    }
}

@MainActor struct SyncReconciliationTests {
    @Test func newerLocalSeekIsNotOverwrittenByOlderCloudProgress() {
        let defaults=UserDefaults(suiteName:UUID().uuidString)!
        let lib=LocalLibrary(defaults:defaults)
        let movie=Movie(id:"kkphim:x",slug:"x",name:"Film",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let source=PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        lib.record(movie,source:source,position:20,duration:100)
        let old=WatchProgress(movieId:movie.id,episodeSlug:"1",server:"S",position:80,duration:100,updatedAt:1)
        lib.applyCloud(favorites:[],progress:[old],movies:[movie.id:movie])
        #expect(lib.progress[movie.id]?.position == 20)
        #expect(lib.recent.first?.id == movie.id)
    }
}

@MainActor struct PlaybackCoordinatorTests {
    @Test func minimizingPreservesPlaybackAndStoppingClearsIt() {
        let movie=Movie(id:"kkphim:x",slug:"x",name:"Film",originName:"",posterURL:nil,backdropURL:nil,year:nil)
        let source=PlaybackSource(server:"S",name:"1",slug:"1",url:"https://example.com/1.m3u8")
        let playback=PlaybackCoordinator()
        playback.open(movie:movie,source:source,sources:[source])
        #expect(playback.isExpanded)
        playback.minimize()
        #expect(!playback.isExpanded)
        #expect(playback.player != nil)
        playback.stop()
        #expect(playback.player == nil)
    }
}
