import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    var errorDescription: String? { "Không thể tải dữ liệu phim. Vui lòng thử lại." }
}

struct APIClient {
    static let shared = APIClient()
    private var backend: URL? { AuthConfiguration.load()?.backendURL }
    private var base: URL { backend ?? URL(string:"https://phimapi.com")! }
    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KomeCine/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { throw APIError.invalidResponse }
        return data
    }
    private func page(_ data:Data) throws -> [Movie] { if backend != nil { return try JSONDecoder().decode(MoviePage.self,from:data).items }; return try KKPhimAdapter.decodePage(data) }
    func latest(page: Int = 1) async throws -> [Movie] { try self.page(await get(backend == nil ? "/danh-sach/phim-moi-cap-nhat" : "/v1/home", query: [.init(name:"page",value:String(page))])) }
    func browse(_ kind: String, page: Int = 1, category: String = "", country: String = "", year: String = "") async throws -> [Movie] {
        var query = [URLQueryItem(name:"page",value:String(page))]
        for (key,value) in [("category",category),("country",country),("year",year)] where !value.isEmpty { query.append(.init(name:key,value:value)) }
        if backend != nil { query.append(.init(name:"kind",value:kind)) }
        return try self.page(await get(backend == nil ? "/v1/api/danh-sach/\(kind)" : "/v1/browse",query:query))
    }
    func search(_ text: String, page: Int = 1, category: String = "", country: String = "", year: String = "") async throws -> [Movie] {
        var query=[URLQueryItem(name:backend == nil ? "keyword" : "q",value:text),.init(name:"page",value:String(page)),.init(name:"limit",value:"24")]
        for (key,value) in [("category",category),("country",country),("year",year)] where !value.isEmpty {query.append(.init(name:key,value:value))}
        return try self.page(await get(backend == nil ? "/v1/api/tim-kiem" : "/v1/search",query:query))
    }
    func detail(_ slug: String) async throws -> MovieDetail {
        guard !slug.contains("/"), !slug.isEmpty else { throw APIError.invalidResponse }
        let data=try await get(backend == nil ? "/phim/\(slug)" : "/v1/movies/\(slug)")
        if backend != nil { return try JSONDecoder().decode(MovieDetail.self,from:data) }; return try KKPhimAdapter.decodeDetail(data)
    }
    func filters() async throws -> Filters {
        if backend != nil { return try JSONDecoder().decode(Filters.self,from:await get("/v1/filters")) }
        async let category = get("/the-loai")
        async let country = get("/quoc-gia")
        func read(_ data: Data) throws -> [FilterItem] {
            let root = KKPhimAdapter.object(try JSONSerialization.jsonObject(with:data))
            return (KKPhimAdapter.object(root["data"])["items"] as? [[String:Any]] ?? []).compactMap { item in
                guard let name = item["name"] as? String, let slug = item["slug"] as? String else { return nil }; return FilterItem(name:name,slug:slug)
            }
        }
        return try await Filters(categories:read(category),countries:read(country))
    }
}
