import Foundation

struct Movie: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    let originName: String
    let posterURL: String?
    let backdropURL: String?
    let year: Int?
}

struct PlaybackSource: Codable, Identifiable, Hashable {
    let server: String
    let name: String
    let slug: String
    let url: String
    var id: String { "\(server):\(slug)" }
    func next(in sources: [PlaybackSource]) -> PlaybackSource? {
        let episodes = sources.filter { $0.server == server }
        guard let index = episodes.firstIndex(of: self), index + 1 < episodes.count else { return nil }
        return episodes[index + 1]
    }
}

struct MovieDetail: Codable {
    let id: String
    let slug: String
    let name: String
    let originName: String
    let posterURL: String?
    let backdropURL: String?
    let year: Int?
    let description: String
    let type: String
    let status: String
    let duration: String
    let quality: String
    let language: String
    let categories: [String]
    let countries: [String]
    let sources: [PlaybackSource]
    var movie: Movie { Movie(id: id, slug: slug, name: name, originName: originName, posterURL: posterURL, backdropURL: backdropURL, year: year) }
}

struct MoviePage: Decodable { let items: [Movie] }
struct RankedMovie: Decodable, Identifiable {
    let rank: Int
    let type: String
    let movie: Movie
    var id: String { movie.id }
}
struct Rankings: Decodable { let series: [RankedMovie]; let movies: [RankedMovie] }
struct FilterItem: Decodable, Identifiable { let name: String; let slug: String; var id: String { slug } }
struct Filters: Decodable { let categories: [FilterItem]; let countries: [FilterItem] }
struct WatchProgress: Codable {
    let movieId: String
    let episodeSlug: String
    let server: String
    let position: Double
    let duration: Double
    let updatedAt: Int64
    static func mostRecent(_ a: Self, _ b: Self) -> Self { a.updatedAt >= b.updatedAt ? a : b }
}
