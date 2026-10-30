import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: OfflineDownloads
    @EnvironmentObject private var playback: PlaybackCoordinator
    var body: some View {
        List {
            ForEach(downloads.records) { record in
                HStack(alignment:.top, spacing:14) {
                    Poster(url:record.movie.posterURL, fallbackURL:record.movie.backdropURL).frame(width:64, height:90).clipShape(RoundedRectangle(cornerRadius:8))
                    VStack(alignment:.leading, spacing:8) {
                        Text(record.movie.name).font(.headline).lineLimit(2)
                        Text("\(record.source.name) · \(record.source.server)").font(.caption).foregroundStyle(.secondary)
                        switch record.status {
                        case .downloading:
                            ProgressView(value:record.progress)
                            HStack { Text("Đang tải \(Int(record.progress * 100))%"); Spacer(); Button("Hủy") { downloads.cancel(record.id) } }.font(.caption)
                        case .ready:
                            if downloads.localURL(movie:record.movie, source:record.source) != nil {
                                Button { playback.open(movie:record.movie, source:record.source, sources:[record.source]) } label: { Label("Xem ngoại tuyến", systemImage:"play.fill") }
                            } else {
                                Text("Bản tải không còn trên máy.").font(.caption).foregroundStyle(.secondary)
                                retry(record)
                            }
                        case .failed:
                            Text(record.error ?? "Tải chưa hoàn tất.").font(.caption).foregroundStyle(.secondary)
                            retry(record)
                        }
                    }
                }.padding(.vertical,6)
                .swipeActions { Button("Xóa", role:.destructive) { downloads.remove(record.id) } }
            }
        }
        .overlay { if downloads.records.isEmpty { ContentUnavailableView("Chưa có phim đã tải", systemImage:"arrow.down.circle", description:Text("Mở menu của player để tải tập phim về máy.")) } }
        .navigationTitle("Tải xuống").navigationBarTitleDisplayMode(.inline)
    }
    private func retry(_ record: DownloadRecord) -> some View {
        Button("Tải lại") { downloads.download(movie:record.movie, source:record.source) }.font(.caption.bold())
    }
}
