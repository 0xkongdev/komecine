import Testing
import UIKit
@testable import KomeCine

@MainActor struct PosterImageLoaderTests {
    private func loader() -> PosterImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PosterImageProtocol.self]
        return PosterImageLoader(session: URLSession(configuration: configuration))
    }

    @Test func timedOutPosterUsesBackdrop() async throws {
        let poster = PosterImageProtocol.route([.failure(URLError(.timedOut))])
        let backdrop = PosterImageProtocol.route([.image])
        let image = await loader().load(url: poster, fallbackURL: backdrop)
        #expect(image != nil)
        #expect(PosterImageProtocol.requests(backdrop) == 1)
    }

    @Test func transientFailureIsRetried() async throws {
        let poster = PosterImageProtocol.route([.status(503), .image])
        let image = await loader().load(url: poster, fallbackURL: nil)
        #expect(image != nil)
        #expect(PosterImageProtocol.requests(poster) == 2)
    }

    @Test func invalidImageUsesBackdrop() async throws {
        let poster = PosterImageProtocol.route([.invalidImage])
        let backdrop = PosterImageProtocol.route([.image])
        #expect(await loader().load(url: poster, fallbackURL: backdrop) != nil)
    }

    @Test func successfulImageIsCached() async throws {
        let poster = PosterImageProtocol.route([.image, .failure(URLError(.notConnectedToInternet))])
        let loader = loader()
        #expect(await loader.load(url: poster, fallbackURL: nil) != nil)
        #expect(await loader.load(url: poster, fallbackURL: nil) != nil)
        #expect(PosterImageProtocol.requests(poster) == 1)
    }

    @Test func missingPosterUsesBackdrop() async throws {
        let backdrop = PosterImageProtocol.route([.image])
        #expect(await loader().load(url: nil, fallbackURL: backdrop) != nil)
    }

    @Test func unavailableCatalogArtworkStillUsesOriginalPoster() async throws {
        let catalog = PosterImageProtocol.route([.status(404)])
        let original = PosterImageProtocol.route([.image])
        #expect(await loader().load(url: catalog, fallbackURL: nil, alternateURL: original) != nil)
    }

    @Test func cancellationDoesNotStartFallbackOrRetry() async throws {
        let poster = PosterImageProtocol.route([.failure(URLError(.cancelled))])
        let backdrop = PosterImageProtocol.route([.image])
        #expect(await loader().load(url: poster, fallbackURL: backdrop) == nil)
        #expect(PosterImageProtocol.requests(poster) == 1)
        #expect(PosterImageProtocol.requests(backdrop) == 0)
    }

    @Test func slowStreamingPosterReachesFallbackBeforeItFinishes() async throws {
        let poster = PosterImageProtocol.route([.slowImage])
        let backdrop = PosterImageProtocol.route([.image])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PosterImageProtocol.self]
        let loader = PosterImageLoader(session: URLSession(configuration: configuration), requestDeadline: .milliseconds(80))
        #expect(await loader.load(url: poster, fallbackURL: backdrop) != nil)
        #expect(PosterImageProtocol.requests(backdrop) == 1)
    }

    @Test func corruptCachedResponseIsReplacedByFreshImage() async throws {
        let poster = PosterImageProtocol.route([.image])
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let request = URLRequest(url: URL(string: poster)!)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=3600"])!
        let corrupt = Data("broken image".utf8)
        cache.storeCachedResponse(CachedURLResponse(response: response, data: corrupt), for: request)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = cache
        configuration.protocolClasses = [PosterImageProtocol.self]
        #expect(await PosterImageLoader(session: URLSession(configuration: configuration)).load(url: poster, fallbackURL: nil) != nil)
        #expect(cache.cachedResponse(for: request)?.data != corrupt)
    }
}

private final class PosterImageProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case image, slowImage, invalidImage, status(Int), failure(URLError)
    }
    private static let lock = NSLock()
    private static var replies: [String: [Reply]] = [:]
    private static var counts: [String: Int] = [:]
    // A complete, decodable 1 × 1 PNG.
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
    private var delivery: Task<Void, Never>?

    static func route(_ values: [Reply]) -> String {
        let url = "https://posters.example/\(UUID().uuidString).png"
        lock.lock(); defer { lock.unlock() }
        replies[url] = values
        return url
    }
    static func requests(_ url: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[url, default: 0]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.lock.lock()
        let index = Self.counts[url.absoluteString, default: 0]
        Self.counts[url.absoluteString] = index + 1
        let plan = Self.replies[url.absoluteString] ?? []
        let reply = index < plan.count ? plan[index] : .status(404)
        Self.lock.unlock()
        if case .failure(let error) = reply {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let status: Int
        let data: Data
        switch reply {
        case .image, .slowImage: status = 200; data = Self.png
        case .invalidImage: status = 200; data = Data("not an image".utf8)
        case .status(let code): status = code; data = Data()
        case .failure: return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if case .slowImage = reply {
            delivery = Task {
                for byte in data {
                    do { try await Task.sleep(for: .milliseconds(20)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    client?.urlProtocol(self, didLoad: Data([byte]))
                }
                client?.urlProtocolDidFinishLoading(self)
            }
            return
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { delivery?.cancel() }
}
