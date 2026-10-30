import UIKit
import ImageIO

actor PosterImageLoader {
    static let shared = PosterImageLoader()
    private let session: URLSession
    private let images = NSCache<NSURL, UIImage>()
    private let requestDeadline: Duration

    init(session: URLSession? = nil, requestDeadline: Duration = .seconds(15)) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                              diskCapacity: 128 * 1024 * 1024,
                                              diskPath: "KomeCinePosters")
            self.session = URLSession(configuration: configuration)
        }
        self.requestDeadline = requestDeadline
        images.totalCostLimit = 48 * 1024 * 1024
    }

    func load(url: String?, fallbackURL: String?, alternateURL: String? = nil) async -> UIImage? {
        var candidates: [URL] = []
        for value in [url, alternateURL, fallbackURL] {
            guard let value, let candidate = URL(string: value),
                  ["http", "https"].contains(candidate.scheme?.lowercased() ?? ""),
                  !candidates.contains(candidate) else { continue }
            candidates.append(candidate)
        }
        guard !Task.isCancelled else { return nil }
        // A cached backdrop can fill the card immediately while the source is slow.
        for candidate in candidates {
            if let image = images.object(forKey: candidate as NSURL) { return image }
            let request = URLRequest(url: candidate)
            if let cached = session.configuration.urlCache?.cachedResponse(for: request) {
                if let status = (cached.response as? HTTPURLResponse)?.statusCode,
                   (200..<300).contains(status), let image = decode(cached.data) {
                    store(image, for: candidate)
                    return image
                }
                session.configuration.urlCache?.removeCachedResponse(for: request)
            }
        }
        var retry: [URL] = []
        for attempt in 0..<2 {
            for candidate in attempt == 0 ? candidates : retry {
                guard !Task.isCancelled else { return nil }
                var request = URLRequest(url: candidate, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                do {
                    let (data, response) = try await fetch(request)
                    guard !Task.isCancelled else { return nil }
                    guard let status = (response as? HTTPURLResponse)?.statusCode else { continue }
                    if (200..<300).contains(status), let image = decode(data) {
                        store(image, for: candidate)
                        return image
                    }
                    session.configuration.urlCache?.removeCachedResponse(for: request)
                    if attempt == 0, status == 408 || status == 429 || status >= 500 { retry.append(candidate) }
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
                    if attempt == 0 { retry.append(candidate) }
                }
            }
            guard attempt == 0, !retry.isEmpty else { break }
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return nil }
        }
        return nil
    }

    private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = session
        let deadline = requestDeadline
        return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await session.data(for: request) }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            // Unlike URLRequest's idle timeout, this also bounds trickling transfers.
            return try await group.next()!
        }
    }

    private func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) != nil,
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func store(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: url as NSURL, cost: cost)
    }
}
