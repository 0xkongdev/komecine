import Foundation
import Combine

struct SubtitleSegment {
    let url: URL
    let start: Double
    let periodStart: Double
}

/// Fetches only subtitle segments around the current playback clock.
@MainActor final class SubtitleController: ObservableObject {
    @Published private(set) var primaryText = ""
    @Published private(set) var secondaryText = ""
    @Published private(set) var error: String?
    private var tracks: [HLSTextTrack] = []
    private var playlists: [String: [SubtitleSegment]] = [:]
    private var cues: [String: [SubtitleCue]] = [:]
    private var fetched: Set<URL> = []
    private var origins: [String: Double] = [:]
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var clock: Double = 0
    private let resource: (URL) async throws -> (String, URL)
    var onFailure: (String) -> Void = { _ in }

    init(resource: @escaping (URL) async throws -> (String, URL) = HLSMetadata.resource) { self.resource = resource }

    func select(primary: HLSTextTrack?, secondary: HLSTextTrack?) {
        task?.cancel(); generation = UUID(); task = nil
        tracks = [primary, secondary].compactMap { $0 }
        playlists = [:]; cues = [:]; fetched = []; origins = [:]
        primaryText = ""; secondaryText = ""; error = nil
        update(time: clock)
    }
    func update(time: Double) {
        guard time.isFinite else { return }
        clock = time
        primaryText = tracks.first.map { WebVTT.text(at: time, cues: cues[$0.id] ?? []) } ?? ""
        secondaryText = tracks.count > 1 ? WebVTT.text(at: time, cues: cues[tracks[1].id] ?? []) : ""
        guard !tracks.isEmpty, task == nil, error == nil else { return }
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.task = nil } }
            do {
                for track in self.tracks {
                    if self.playlists[track.id] == nil {
                        let (text, url) = try await self.resource(track.url)
                        guard !Task.isCancelled, self.generation == token else { return }
                        if text.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("WEBVTT") {
                            self.cues[track.id] = WebVTT.parse(text)
                            self.playlists[track.id] = []
                        } else {
                            self.playlists[track.id] = Self.segments(text, baseURL: url)
                        }
                    }
                    let segments = self.playlists[track.id] ?? []
                    if !segments.isEmpty {
                        let index = segments.lastIndex(where: { $0.start <= self.clock }) ?? 0
                        let nearby = segments[max(0, index - 1)...min(segments.count - 1, index + 1)]
                        for part in nearby {
                            let periodKey = "\(track.id)|\(part.periodStart)"
                            if self.origins[periodKey] == nil, let first = segments.first(where: { $0.periodStart == part.periodStart }) {
                                let (text, _) = try await self.resource(first.url)
                                guard !Task.isCancelled, self.generation == token else { return }
                                self.origins[periodKey] = (WebVTT.mapOffset(text) ?? 0) - first.start
                            }
                            guard !self.fetched.contains(part.url) else { continue }
                            let (text, _) = try await self.resource(part.url)
                            guard !Task.isCancelled, self.generation == token else { return }
                            let values = WebVTT.aligned(text,origin:self.origins[periodKey] ?? 0)
                            self.cues[track.id] = Array(Set((self.cues[track.id] ?? []) + values)).sorted { $0.start < $1.start }
                            self.fetched.insert(part.url)
                        }
                    }
                }
                guard self.generation == token else { return }
                self.primaryText = self.tracks.first.map { WebVTT.text(at:self.clock, cues:self.cues[$0.id] ?? []) } ?? ""
                self.secondaryText = self.tracks.count > 1 ? WebVTT.text(at:self.clock, cues:self.cues[self.tracks[1].id] ?? []) : ""
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.error = "Không tải được phụ đề. Hãy chọn lại ngôn ngữ để thử lại."
                self.primaryText = ""; self.secondaryText = ""
                self.onFailure(self.error!)
            }
        }
    }
    static func segments(_ text: String, baseURL: URL) -> [SubtitleSegment] {
        var result: [SubtitleSegment] = []
        var start = 0.0, duration = 0.0, period = 0.0
        for raw in text.components(separatedBy:.newlines) {
            let line = raw.trimmingCharacters(in:.whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") { duration = Double(line.dropFirst(8).split(separator:",").first ?? "") ?? 0 }
            else if line == "#EXT-X-DISCONTINUITY" { period = start }
            else if !line.isEmpty, !line.hasPrefix("#"), let url = HLSMetadata.resolve(line, base:baseURL) {
                result.append(SubtitleSegment(url:url, start:start, periodStart:period)); start += max(0, duration)
            }
        }
        return result
    }
}
