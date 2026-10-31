import Foundation
import Combine

@MainActor final class LocalLibrary: ObservableObject {
    @Published private(set) var favorites: [Movie] = []
    @Published private(set) var recent: [Movie] = []
    @Published private(set) var progress: [String: WatchProgress] = [:]
    @Published private(set) var posterFallbacks: [String: String] = [:]
    var onFavoriteChange: ((Movie, Bool) -> Void)?
    var onProgressChange: ((WatchProgress) -> Void)?
    private let defaults: UserDefaults
    private var account: String?
    var accountID: String? { account }
    private var episodeHistory: [String: WatchProgress] = [:]
    private var artworkCandidates: [Movie] = []
    private func key(_ name: String) -> String { (account.map { "user.\($0)." } ?? "guest.") + name }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Self.decode([Movie].self, defaults.data(forKey: "guest.favorites")) ?? []
        recent = Self.decode([Movie].self, defaults.data(forKey: "guest.recent")) ?? []
        progress = Self.decode([String: WatchProgress].self, defaults.data(forKey: "guest.progress")) ?? [:]
        episodeHistory = Self.decode([String: WatchProgress].self, defaults.data(forKey: "guest.episodeHistory")) ?? [:]
        posterFallbacks = Self.decode([String: String].self, defaults.data(forKey: "guest.posterFallbacks")) ?? [:]
    }
    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? { guard let data else { return nil }; return try? JSONDecoder().decode(type, from: data) }
    private func save<T: Encodable>(_ value: T, for key: String) { defaults.set(try? JSONEncoder().encode(value), forKey: self.key(key)) }
    func updatePosterFallbacks(from candidates: [Movie]) {
        artworkCandidates = candidates
        refreshPosterFallbacks()
    }
    private func refreshPosterFallbacks() {
        func title(_ movie: Movie) -> String {
            movie.originName.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        var updated = posterFallbacks
        for movie in recent + favorites {
            let original = title(movie)
            guard let year = movie.year, !original.isEmpty,
                  let match = artworkCandidates.first(where: { $0.id != movie.id && $0.year == year && title($0) == original }),
                  let image = match.posterURL ?? match.backdropURL,
                  let url = URL(string: image), url.scheme?.lowercased() == "https" else { continue }
            updated[movie.id] = image
        }
        guard updated != posterFallbacks else { return }
        posterFallbacks = updated
        save(updated, for: "posterFallbacks")
    }
    func setAccount(_ newAccount: String?) {
        guard newAccount != account else { return }
        let guestFavorites = account == nil && newAccount != nil ? favorites : []
        let guestRecent = account == nil && newAccount != nil ? recent : []
        let guestProgress = account == nil && newAccount != nil ? progress : [:]
        let guestEpisodes = account == nil && newAccount != nil ? episodeHistory : [:]
        let guestPosters = account == nil && newAccount != nil ? posterFallbacks : [:]
        account = newAccount
        favorites = Self.decode([Movie].self, defaults.data(forKey:key("favorites"))) ?? []
        recent = Self.decode([Movie].self, defaults.data(forKey:key("recent"))) ?? []
        progress = Self.decode([String:WatchProgress].self, defaults.data(forKey:key("progress"))) ?? [:]
        episodeHistory = Self.decode([String:WatchProgress].self, defaults.data(forKey:key("episodeHistory"))) ?? [:]
        posterFallbacks = Self.decode([String:String].self, defaults.data(forKey:key("posterFallbacks"))) ?? [:]
        for movie in guestFavorites where !favorites.contains(where: {$0.id == movie.id}) { favorites.append(movie) }
        for movie in guestRecent where !recent.contains(where: {$0.id == movie.id}) { recent.append(movie) }
        for (id, value) in guestProgress { progress[id] = progress[id].map { WatchProgress.mostRecent($0, value) } ?? value }
        for (id, value) in guestEpisodes { episodeHistory[id] = episodeHistory[id].map { WatchProgress.mostRecent($0, value) } ?? value }
        posterFallbacks.merge(guestPosters) { current, _ in current }
        if newAccount != nil {
            save(favorites,for:"favorites"); save(recent,for:"recent"); save(progress,for:"progress")
            save(episodeHistory, for:"episodeHistory")
            save(posterFallbacks,for:"posterFallbacks")
            defaults.removeObject(forKey:"guest.favorites"); defaults.removeObject(forKey:"guest.recent"); defaults.removeObject(forKey:"guest.progress")
            defaults.removeObject(forKey:"guest.posterFallbacks")
            defaults.removeObject(forKey:"guest.episodeHistory")
        }
        refreshPosterFallbacks()
    }
    func applyCloud(favorites: [Movie], progress: [WatchProgress], movies: [String:Movie]) {
        self.favorites=favorites
        var merged=Dictionary(progress.map { ($0.movieId,$0) },uniquingKeysWith: { WatchProgress.mostRecent($0,$1) })
        for (id, local) in self.progress { merged[id] = merged[id].map { WatchProgress.mostRecent(local,$0) } ?? local }
        let localMovies=Dictionary(self.recent.map { ($0.id,$0) },uniquingKeysWith: { first,_ in first })
        self.progress=merged
        self.recent=merged.values.sorted { $0.updatedAt > $1.updatedAt }.compactMap { movies[$0.movieId] ?? localMovies[$0.movieId] }
        save(self.favorites,for:"favorites"); save(self.progress,for:"progress"); save(self.recent,for:"recent")
        refreshPosterFallbacks()
    }
    func clearAccount(_ id: String) {
        for name in ["favorites","recent","progress","posterFallbacks","episodeHistory"] { defaults.removeObject(forKey:"user.\(id).\(name)") }
    }
    func toggleFavorite(_ movie: Movie) {
        if favorites.contains(where: {$0.id == movie.id}) { favorites.removeAll {$0.id == movie.id} } else { favorites.insert(movie, at: 0) }
        save(favorites, for: "favorites")
        refreshPosterFallbacks()
        onFavoriteChange?(movie, favorites.contains(where: { $0.id == movie.id }))
    }
    func record(_ movie: Movie, source: PlaybackSource, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, position >= 0, duration >= 0 else { return }
        recent.removeAll {$0.id == movie.id}; recent.insert(movie, at: 0)
        progress[movie.id] = WatchProgress(movieId:movie.id,episodeSlug:source.slug,server:source.server,position:position,duration:duration,updatedAt:Int64(Date().timeIntervalSince1970 * 1000))
        episodeHistory[episodeKey(movieID: movie.id, source: source)] = progress[movie.id]
        save(episodeHistory, for:"episodeHistory")
        save(recent, for:"recent"); save(progress, for:"progress")
        refreshPosterFallbacks()
        if let value=progress[movie.id] {onProgressChange?(value)}
    }
    private func episodeKey(movieID: String, source: PlaybackSource) -> String {
        (try? String(data: JSONEncoder().encode([movieID, source.server, source.slug]), encoding: .utf8)) ?? ""
    }
    func episodeProgress(movieID: String, source: PlaybackSource) -> WatchProgress? {
        let saved = episodeHistory[episodeKey(movieID: movieID, source: source)]
        guard let latest = progress[movieID], latest.episodeSlug == source.slug, latest.server == source.server else { return saved }
        return saved.map { WatchProgress.mostRecent($0, latest) } ?? latest
    }
}
