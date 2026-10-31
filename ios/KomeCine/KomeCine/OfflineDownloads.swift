import Foundation
import AVFoundation
import Combine
import UIKit

struct DownloadRecord: Codable, Identifiable {
    enum Status: String, Codable { case downloading, ready, failed }
    var id = UUID().uuidString
    let movie: Movie
    let source: PlaybackSource
    var owner: String
    var status: Status = .downloading
    var progress = 0.0
    var assetPath: String?
    var error: String?
    var createdAt = Date()
}

@MainActor final class OfflineDownloads: NSObject, ObservableObject {
    static let shared = OfflineDownloads()
    static let sessionIdentifier = "app.komecine.offline-assets"
    @Published private(set) var records: [DownloadRecord] = []
    private var all: [DownloadRecord]
    private var owner = "guest"
    private let defaults: UserDefaults
    private let identifier: String
    var backgroundCompletion: (() -> Void)?
    private var restored = false
    private lazy var session = AVAssetDownloadURLSession(configuration:.background(withIdentifier:identifier), assetDownloadDelegate:self, delegateQueue:.main)

    init(defaults: UserDefaults = .standard, identifier: String = "app.komecine.offline-assets") {
        self.defaults = defaults; self.identifier = identifier
        all = defaults.data(forKey:"offline.records").flatMap { try? JSONDecoder().decode([DownloadRecord].self, from:$0) } ?? []
        super.init(); publish()
    }
    func setAccount(_ id: String?) {
        let next = id ?? "guest"
        if owner == "guest", next != "guest" {
            for index in all.indices where all[index].owner == "guest" { all[index].owner = next }
        }
        owner = next; persist()
    }
    func store(_ record: DownloadRecord) {
        if let index = all.firstIndex(where: { $0.id == record.id }) { all[index] = record }
        else { all.append(record) }
        persist()
    }
    func updateProgress(id: String, fraction: Double) {
        guard fraction.isFinite, let index = all.firstIndex(where: { $0.id == id }), all[index].status == .downloading else { return }
        all[index].progress = max(all[index].progress, min(1, max(0, fraction))); persist()
    }
    func localURL(movie: Movie, source: PlaybackSource) -> URL? {
        guard let record = records.first(where: { $0.movie.id == movie.id && $0.source.id == source.id && $0.status == .ready }),
              let path = record.assetPath else { return nil }
        let url = URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath:url.path), AVURLAsset(url:url).assetCache?.isPlayableOffline == true else { return nil }
        return url
    }
    func download(movie: Movie, source: PlaybackSource) {
        if let existing = records.first(where: { $0.movie.id == movie.id && $0.source.id == source.id }) {
            if existing.status == .downloading || localURL(movie:movie, source:source) != nil { return }
            remove(existing.id)
        }
        var record = DownloadRecord(movie:movie, source:source, owner:owner)
        guard let url = URL(string:source.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            record.status = .failed; record.error = "Nguồn này không hỗ trợ tải xuống."; store(record); return
        }
        let asset = AVURLAsset(url:url)
        guard let task = session.makeAssetDownloadTask(asset:asset, assetTitle:"\(movie.name) · \(source.name)", assetArtworkData:nil, options:nil) else {
            record.status = .failed; record.error = "Không tạo được bản tải cho nguồn này."; store(record); return
        }
        task.taskDescription = record.id; store(record); task.resume()
    }
    func cancel(_ id: String) { remove(id) }
    func remove(_ id: String) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        session.getAllTasks { tasks in tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() } }
        if let path = record.assetPath { try? FileManager.default.removeItem(at:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent(path)) }
        all.removeAll { $0.id == id }; persist()
    }
    func restoreTasks() {
        guard !restored else { return }; restored = true
        session.getAllTasks { [weak self] tasks in
            let ids = Set(tasks.compactMap(\.taskDescription))
            Task { @MainActor [weak self] in
                guard let self else { return }
                for index in self.all.indices where self.all[index].status == .downloading && !ids.contains(self.all[index].id) {
                    if let path = self.all[index].assetPath,
                       AVURLAsset(url:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent(path)).assetCache?.isPlayableOffline == true {
                        self.all[index].status = .ready; self.all[index].progress = 1
                    } else {
                        self.all[index].status = .failed; self.all[index].error = "Lượt tải đã gián đoạn. Chọn tải lại để tiếp tục."
                    }
                }
                self.persist()
            }
        }
    }
    private func publish() { records = all.filter { $0.owner == owner }.sorted { $0.createdAt > $1.createdAt } }
    private func persist() { defaults.set(try? JSONEncoder().encode(all), forKey:"offline.records"); publish() }
    private func didDownload(id: String, location: URL) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { try? FileManager.default.removeItem(at:location); return }
        let home = URL(fileURLWithPath:NSHomeDirectory()).path + "/"
        guard location.path.hasPrefix(home) else { return }
        all[index].assetPath = String(location.path.dropFirst(home.count)); persist()
    }
    private func completed(id: String, error: Error?) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        if error != nil {
            all[index].status = .failed; all[index].error = "Không tải được nguồn này. Kiểm tra mạng rồi thử lại."
        } else if let path = all[index].assetPath,
                  AVURLAsset(url:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent(path)).assetCache?.isPlayableOffline == true {
            all[index].status = .ready; all[index].progress = 1; all[index].error = nil
        } else {
            all[index].status = .failed; all[index].error = "Nguồn phim chưa cung cấp bản xem ngoại tuyến dùng được."
        }
        persist()
    }
}

extension OfflineDownloads: AVAssetDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in self?.didDownload(id:id, location:location) }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let total = timeRangeExpectedToLoad.duration.seconds
        guard total.isFinite, total > 0 else { return }
        let fraction = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds } / total
        Task { @MainActor [weak self] in self?.updateProgress(id:id, fraction:fraction) }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        Task { @MainActor [weak self] in self?.completed(id:id, error:error) }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in let completion = self?.backgroundCompletion; self?.backgroundCompletion = nil; completion?() }
    }
}

final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == OfflineDownloads.sessionIdentifier else { completionHandler(); return }
        OfflineDownloads.shared.backgroundCompletion = completionHandler
        OfflineDownloads.shared.restoreTasks()
    }
}
