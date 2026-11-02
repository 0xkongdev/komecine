import Foundation
import Network
import Testing
@testable import KomeCine

struct PlaybackSourceFailureTests {
    @Test func hlsResourcePreservesMissingSourceStatus() async throws {
        let server = try PlaybackHTTPFixture(status: 404)
        let url = try await server.start()
        defer { server.stop() }
        do {
            _ = try await HLSMetadata.resource(url)
            Issue.record("A missing manifest must fail with its HTTP status")
        } catch HLSResourceError.httpStatus(let status) {
            #expect(status == 404)
        }
    }

    @MainActor @Test func missingVideoExplainsSourceAvailabilityAndStopsBuffering() async throws {
        let server = try PlaybackHTTPFixture(status: 404)
        let url = try await server.start()
        defer { server.stop() }
        let playback = PlaybackCoordinator()
        let source = source(url)
        playback.open(movie: movie, source: source, sources: [source])
        defer { playback.stop() }
        for _ in 0..<400 {
            if playback.error?.contains("máy chủ nguồn") == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(playback.error?.contains("máy chủ nguồn") == true)
        #expect(!playback.isBuffering)
        #expect(!playback.isPlaying)
    }

    @MainActor @Test func optionalMetadata404DoesNotBlockPlayableVideo() async throws {
        let video = try #require(Bundle.main.url(forResource: "player-preview", withExtension: "mp4"))
        let server = try PlaybackHTTPFixture(status: 200, body: Data(contentsOf: video), contentType: "video/mp4")
        let url = try await server.start(path: "video.mp4")
        defer { server.stop() }
        let playback = PlaybackCoordinator(loadMetadata: { _ in throw HLSResourceError.httpStatus(404) })
        let source = source(url)
        playback.open(movie: movie, source: source, sources: [source])
        defer { playback.stop() }
        for _ in 0..<400 {
            if playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(playback.isPlaying)
        #expect(playback.error == nil)
    }

    @MainActor @Test func lateMissingSourceResultCannotAffectAnotherEpisode() async throws {
        let server = try PlaybackHTTPFixture(status: 404)
        let url = try await server.start()
        defer { server.stop() }
        let video = try #require(Bundle.main.url(forResource: "player-preview", withExtension: "mp4"))
        let playback = PlaybackCoordinator(loadMetadata: { _ in
            // Deliberately finish after cancellation to exercise the session guard.
            try? await Task.sleep(for: .milliseconds(200))
            throw HLSResourceError.httpStatus(404)
        })
        let missing = source(url)
        let available = PlaybackSource(server: "Vietsub", name: "Tập 24", slug: "tap-24", url: video.absoluteString)
        playback.open(movie: movie, source: missing, sources: [missing, available])
        await Task.yield()
        playback.change(to: available)
        defer { playback.stop() }
        for _ in 0..<400 {
            if playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(playback.source == available)
        #expect(playback.isPlaying)
        #expect(playback.error == nil)
    }

    private var movie: Movie {
        Movie(id: "source-failure", slug: "source-failure", name: "Movie", originName: "", posterURL: nil, backdropURL: nil, year: nil)
    }
    private func source(_ url: URL) -> PlaybackSource {
        PlaybackSource(server: "Vietsub", name: "Tập 26", slug: "tap-26", url: url.absoluteString)
    }
}

/// Real loopback HTTP responses exercise both URLSession and AVPlayer without a live CDN.
private final class PlaybackHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "KomeCine.PlaybackHTTPFixture")

    init(status: Int, body: Data = Data(), contentType: String = "text/plain") throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let queue = queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                var code = status
                var content = body
                var rangeHeader = ""
                // AVPlayer probes MP4 files with byte range requests.
                if status == 200,
                   let range = request.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("range: bytes=") }) {
                    let bounds = range.split(separator: "=")[1].split(separator: "-", omittingEmptySubsequences: false)
                    let start = Int(bounds[0]) ?? 0
                    let end = min(body.count - 1, Int(bounds[1]) ?? body.count - 1)
                    if start >= 0, start <= end {
                        code = 206
                        content = body.subdata(in: start..<(end + 1))
                        rangeHeader = "Content-Range: bytes \(start)-\(end)/\(body.count)\r\n"
                    }
                }
                var payload = Data("HTTP/1.1 \(code) Response\r\nContent-Type: \(contentType)\r\nContent-Length: \(content.count)\r\nAccept-Ranges: bytes\r\n\(rangeHeader)Connection: close\r\n\r\n".utf8)
                if !request.hasPrefix("HEAD ") { payload.append(content) }
                connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    func start(path: String = "video.m3u8") async throws -> URL {
        let listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/\(path)")!)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }
}
