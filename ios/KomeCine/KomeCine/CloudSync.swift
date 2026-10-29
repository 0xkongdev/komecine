import Foundation
import Combine

private struct Mutation: Codable {
    let kind:String
    let movie:Movie?
    let progress:WatchProgress?
}
private struct ResponseItems<T:Decodable>:Decodable { let items:[T] }

@MainActor final class CloudSync:ObservableObject {
    @Published private(set) var isSyncing=false
    @Published private(set) var error:String?
    private var flushing=false
    private var resyncRequested=false
    private let defaults:UserDefaults
    private weak var library:LocalLibrary?
    private weak var auth:AuthManager?
    private var lastProgress:Date = .distantPast
    init(defaults:UserDefaults = .standard) {self.defaults=defaults}
    func configure(library:LocalLibrary,auth:AuthManager) {
        self.library=library; self.auth=auth
        library.onFavoriteChange = { [weak self] movie,added in self?.enqueue(Mutation(kind:added ? "favorite.put" : "favorite.delete",movie:movie,progress:nil)) }
        library.onProgressChange = { [weak self] value in
            guard let self else{return}
            if Date().timeIntervalSince(self.lastProgress)>=30 {self.lastProgress=Date(); self.enqueue(Mutation(kind:"progress.put",movie:nil,progress:value))}
        }
    }
    func activate(_ id:String?,previousID:String?) {
        guard let library else{return}
        let guestFavorites = previousID == nil && id != nil ? library.favorites : []
        let guestProgress = previousID == nil && id != nil ? Array(library.progress.values) : []
        library.setAccount(id)
        if id == nil, let previousID { library.clearAccount(previousID) }
        guard id != nil else{return}
        for movie in guestFavorites {enqueue(Mutation(kind:"favorite.put",movie:movie,progress:nil))}
        for progress in guestProgress {enqueue(Mutation(kind:"progress.put",movie:nil,progress:progress))}
        Task { await synchronize() }
    }
    func saveProgressNow() {
        guard let library else{return}
        for progress in library.progress.values {enqueue(Mutation(kind:"progress.put",movie:nil,progress:progress))}
    }
    private func pendingKey(_ id:String)->String {"sync.pending.\(id)"}
    private func pending(_ id:String)->[Mutation] { guard let data=defaults.data(forKey:pendingKey(id)) else{return []}; return (try? JSONDecoder().decode([Mutation].self,from:data)) ?? [] }
    private func save(_ values:[Mutation],_ id:String) {defaults.set(try? JSONEncoder().encode(values),forKey:pendingKey(id))}
    private func enqueue(_ mutation:Mutation) {
        guard let id=auth?.userID, auth?.token != nil else{return}
        var values=pending(id); values.append(mutation); save(values,id)
        Task { await synchronize() }
    }
    private func request(_ path:String, method:String="GET", data:Data?=nil, auth:AuthManager) async throws -> Data {
        guard let config=auth.configuration, let token=auth.token else {throw APIError.invalidResponse}
        guard let url=URL(string:path,relativeTo:config.backendURL)?.absoluteURL else {throw APIError.invalidResponse}
        var request=URLRequest(url:url);request.httpMethod=method;request.httpBody=data
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        if data != nil {request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (body,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse).map({(200..<300).contains($0.statusCode)}) == true else {throw APIError.invalidResponse}
        return body
    }
    func synchronize() async {
        if flushing { resyncRequested=true; return }
        guard let auth,let id=auth.userID,let library,auth.token != nil else{return}
        flushing=true; isSyncing=true; error=nil
        defer {
            flushing=false; isSyncing=false
            let requested=resyncRequested; resyncRequested=false
            if let current=auth.userID, (current != id && requested) || (current == id && error == nil && (requested || !pending(id).isEmpty)) { Task { await synchronize() } }
        }
        do {
            while let mutation=pending(id).first {
                guard auth.userID==id else{return}
                switch mutation.kind {
                case "favorite.put":
                    guard let movie=mutation.movie, let escaped=movie.id.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed) else {throw APIError.invalidResponse}
                    _=try await request("/v1/me/favorites/\(escaped)",method:"PUT",data:try JSONEncoder().encode(movie),auth:auth)
                case "favorite.delete":
                    guard let movie=mutation.movie, let escaped=movie.id.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed) else {throw APIError.invalidResponse}
                    _=try await request("/v1/me/favorites/\(escaped)",method:"DELETE",auth:auth)
                case "progress.put":
                    guard let value=mutation.progress else {throw APIError.invalidResponse}
                    _=try await request("/v1/me/progress",method:"PUT",data:try JSONEncoder().encode(value),auth:auth)
                default: throw APIError.invalidResponse
                }
                guard auth.userID==id else{return}
                var queue=pending(id); if !queue.isEmpty {queue.removeFirst()}; save(queue,id)
            }
            let favorites = try JSONDecoder().decode(ResponseItems<Movie>.self,from:await request("/v1/me/favorites",auth:auth)).items
            let progress = try JSONDecoder().decode(ResponseItems<WatchProgress>.self,from:await request("/v1/me/progress",auth:auth)).items
            guard auth.userID==id,pending(id).isEmpty else{return}
            var movieCache=Dictionary(uniqueKeysWithValues: (library.recent + library.favorites).map {($0.id,$0)}.reduce(into:[String:Movie]()) { $0[$1.0] = $1.1 }.map {($0.key,$0.value)} )
            for value in progress where movieCache[value.movieId] == nil {
                let slug=value.movieId.hasPrefix("kkphim:") ? String(value.movieId.dropFirst(7)) : value.movieId
                if let detail=try? await APIClient.shared.detail(slug) {movieCache[value.movieId]=detail.movie}
            }
            guard auth.userID==id,pending(id).isEmpty else{return}
            library.applyCloud(favorites:favorites,progress:progress,movies:movieCache)
            let remote=Dictionary(progress.map { ($0.movieId,$0) },uniquingKeysWith: { WatchProgress.mostRecent($0,$1) })
            for local in library.progress.values where remote[local.movieId].map({ local.updatedAt > $0.updatedAt }) ?? true {
                enqueue(Mutation(kind:"progress.put",movie:nil,progress:local))
            }
            error=nil
        } catch {self.error="Chưa thể đồng bộ. Dữ liệu sẽ được gửi lại khi kết nối trở lại."}
    }
}
