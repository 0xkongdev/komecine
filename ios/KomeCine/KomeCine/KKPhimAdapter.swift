import Foundation

enum KKPhimAdapter {
    static func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
    static func string(_ value: Any?) -> String { value as? String ?? "" }
    static func image(_ value: Any?, base: String = "https://phimapi.com/uploads/movies/") -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        let lowercased = value.lowercased()
        let path = lowercased.hasPrefix("uploads/movies/") || lowercased.hasPrefix("upload/") ? "/" + value : value
        guard let url = URL(string: path, relativeTo: URL(string: base))?.absoluteURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }
    static func movie(_ value: [String: Any], base: String = "https://phimapi.com/uploads/movies/") -> Movie {
        let slug = string(value["slug"])
        return Movie(id: "kkphim:\(slug)", slug: slug, name: string(value["name"]), originName: string(value["origin_name"]), posterURL: image(value["poster_url"], base: base), backdropURL: image(value["thumb_url"], base: base), year: value["year"] as? Int)
    }
    static func decodePage(_ data: Data) throws -> [Movie] {
        let root = object(try JSONSerialization.jsonObject(with: data))
        let nested = object(root["data"])
        let items = (root["items"] as? [[String: Any]]) ?? (nested["items"] as? [[String: Any]]) ?? []
        let domain = string(nested["APP_DOMAIN_CDN_IMAGE"])
        let base = (root["pathImage"] as? String) ?? (domain.isEmpty ? "https://phimapi.com/uploads/movies/" : "\(domain)/uploads/movies/")
        return items.map { movie($0, base: base) }.filter { !$0.slug.isEmpty }
    }
    static func decodeDetail(_ data: Data) throws -> MovieDetail {
        let root = object(try JSONSerialization.jsonObject(with: data))
        let raw = object(root["movie"])
        guard !string(raw["slug"]).isEmpty else { throw APIError.invalidResponse }
        let m = movie(raw)
        let servers = root["episodes"] as? [[String: Any]] ?? []
        let sources: [PlaybackSource] = servers.flatMap { server in
            (server["server_data"] as? [[String: Any]] ?? []).compactMap { episode in
                let link = string(episode["link_m3u8"]), slug = string(episode["slug"])
                guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !slug.isEmpty else { return nil }
                return PlaybackSource(server: string(server["server_name"]), name: string(episode["name"]), slug: slug, url: link)
            }
        }
        func names(_ value: Any?) -> [String] { (value as? [[String: Any]] ?? []).map { string($0["name"]) }.filter { !$0.isEmpty } }
        return MovieDetail(id:m.id,slug:m.slug,name:m.name,originName:m.originName,posterURL:m.posterURL,backdropURL:m.backdropURL,year:m.year,description:string(raw["content"]),type:string(raw["type"]),status:string(raw["status"]),duration:string(raw["time"]),quality:string(raw["quality"]),language:string(raw["lang"]),categories:names(raw["category"]),countries:names(raw["country"]),sources:sources)
    }
}
