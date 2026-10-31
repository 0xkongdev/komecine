import SwiftUI

struct PlayerPanels: View {
    let panel: PlayerPanel
    @ObservedObject var playback: PlaybackCoordinator
    @ObservedObject var presentation: PlayerPresentation
    @ObservedObject var downloads: OfflineDownloads
    let favorite: Bool
    var close: () -> Void
    var toggleFavorite: () -> Void
    var screenshot: () -> Void
    var share: () -> Void
    var download: () -> Void

    private var accent: Color { .accentColor }
    private var title: String {
        switch panel {
        case .speed: "Tốc độ phát"
        case .quality: "Chất lượng"
        case .captions: "Âm thanh và phụ đề"
        case .episodes: "Danh sách phát"
        case .servers: "Nguồn phát"
        case .more: "Tùy chọn"
        }
    }
    var body: some View {
        VStack(spacing:0) {
            if panel != .speed {
            HStack { Text(title).font(.headline); Spacer(); Button(action:close) { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("Đóng bảng") }
                .padding(.leading,20).padding(.trailing,6).padding(.top,6)
            Divider().overlay(.white.opacity(0.08))
            }
            ScrollView {
                VStack(alignment:.leading,spacing:panel == .speed ? 0 : 12) { content }.padding(panel == .speed ? 8 : 20)
            }
        }
        .foregroundStyle(.white)
        .background(Color(red:0.085,green:0.085,blue:0.095).opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius:16))
        .accessibilityIdentifier("player.panel.\(panel.rawValue)")
    }
    @ViewBuilder private var content: some View {
        switch panel {
        case .speed:
            ForEach(PlaybackCoordinator.speeds, id:\.self) { speed in
                choice(String(format:"%g×",speed), selected:playback.selectedSpeed == speed) { playback.setSpeed(speed); close() }
                    .accessibilityIdentifier("speed.\(speed)")
            }
        case .quality:
            choice("Tự động", selected:playback.selectedQuality == nil) { playback.selectQuality(nil); close() }
            ForEach(playback.qualities) { quality in
                choice("Tối đa \(quality.title)", selected:playback.selectedQuality == quality.height) { playback.selectQuality(quality.height); close() }
            }
            if playback.metadataLoading { ProgressView("Đang đọc nguồn phim…").tint(.white) }
            else if playback.qualities.isEmpty { hint(playback.usingOfflineAsset ? "Đang phát bản đã tải về máy." : "Nguồn hiện tại không cung cấp nhiều mức chất lượng để chọn.") }
        case .captions: captions
        case .episodes: episodes
        case .servers:
            ForEach(Array(Set(playback.sources.map(\.server))).sorted(), id:\.self) { server in
                choice(server, selected:playback.source?.server == server) { playback.changeServer(to:server); close() }
            }
        case .more: more
        }
    }
    private func choice(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:12) { Text(text).multilineTextAlignment(.leading); Spacer(minLength:0); if selected { Image(systemName:"checkmark").font(.caption.bold()) } }
                .foregroundStyle(selected ? accent : .white).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                .padding(.horizontal,12).padding(.vertical,2)
                .background(selected ? accent.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain)
    }
    private func hint(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.white.opacity(0.6)).lineSpacing(4).padding(.vertical,6) }
    private var captions: some View {
        VStack(alignment:.leading,spacing:14) {
            if !playback.audioTracks.isEmpty {
                Text("Âm thanh").font(.subheadline.bold())
                ForEach(playback.audioTracks) { track in choice(track.name, selected:playback.audioID == track.id) { playback.selectAudio(track.id) } }
                Divider()
            }
            Text("Phụ đề").font(.subheadline.bold())
            choice("Tắt", selected:playback.captionID == nil) { playback.selectCaption(nil) }
            ForEach(playback.captionTracks) { track in choice(track.name, selected:playback.captionID == track.id) { playback.selectCaption(track.id) } }
            if playback.metadataLoading { ProgressView("Đang đọc ngôn ngữ…").tint(.white) }
            else if playback.captionTracks.isEmpty { hint("Nguồn này không có phụ đề rời. Nếu phụ đề đã nằm trong hình, bạn không thể tắt hoặc đổi cỡ chữ.") }
            if playback.captionID != nil {
                Divider(); Text("Kích thước phụ đề").font(.subheadline.bold())
                Slider(value:$playback.captionSize,in:14...32,step:2).accessibilityLabel("Kích thước phụ đề")
            }
            if playback.captionTracks.first(where: { $0.id == playback.captionID })?.external != nil {
                Divider(); Text("Phụ đề song ngữ").font(.subheadline.bold())
                let alternatives = playback.captionTracks.filter { $0.external != nil && $0.id != playback.captionID }
                if alternatives.isEmpty { hint("Nguồn cần ít nhất hai ngôn ngữ phụ đề rời để xem song ngữ.") }
                else {
                    choice("Tắt ngôn ngữ thứ hai", selected:playback.secondaryCaptionID == nil) { playback.selectSecondaryCaption(nil) }
                    ForEach(alternatives) { track in choice(track.name, selected:playback.secondaryCaptionID == track.id) { playback.selectSecondaryCaption(track.id) } }
                    if playback.isInPiP || playback.isExternalPlayback { hint("PiP và AirPlay dùng một ngôn ngữ phụ đề của nguồn. Song ngữ tiếp tục khi quay lại app.") }
                }
            }
        }
    }
    private var episodes: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment:.leading,spacing:12) {
                Text(playback.movie?.name ?? "").font(.subheadline.bold())
                ForEach(Array(Set(playback.sources.map(\.server))).sorted(),id:\.self) { server in
                    Text(server).font(.caption.bold()).foregroundStyle(.white.opacity(0.6)).padding(.top,8)
                    ForEach(playback.sources.filter { $0.server == server }) { episode in
                        Button { playback.change(to:episode); close() } label: {
                            HStack(spacing:12) {
                                ZStack {
                                    Poster(url:playback.movie?.backdropURL, fallbackURL:playback.movie?.posterURL).frame(width:102,height:58).clipped()
                                    if playback.source?.id == episode.id { Image(systemName:"waveform").font(.title3).padding(8).background(.black.opacity(0.6),in:Circle()) }
                                }.clipShape(RoundedRectangle(cornerRadius:6))
                                Text(episode.name.isEmpty ? episode.slug : episode.name).font(.subheadline).frame(maxWidth:.infinity,alignment:.leading)
                            }
                            .padding(6).foregroundStyle(playback.source?.id == episode.id ? accent : .white)
                            .background(playback.source?.id == episode.id ? accent.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain).id(episode.id)
                    }
                }
            }.onAppear { if let id = playback.source?.id { proxy.scrollTo(id,anchor:.center) } }
        }
    }
    private func menuAction(_ text: String, symbol: String, id: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action:action) { Label(text,systemImage:symbol).frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
            .buttonStyle(.plain).accessibilityIdentifier(id ?? text)
    }
    private var more: some View {
        VStack(alignment:.leading,spacing:10) {
            menuAction(favorite ? "Bỏ khỏi danh sách xem" : "Thêm vào danh sách xem",symbol:favorite ? "checkmark.square" : "plus.square", action:toggleFavorite)
            menuAction("Tải tập này",symbol:"arrow.down.circle", action:download)
            if let record = downloads.records.first(where: { $0.movie.id == playback.movie?.id && $0.source.id == playback.source?.id }) {
                if record.status == .downloading { ProgressView(value:record.progress); Text("Đang tải \(Int(record.progress * 100))%").font(.caption) }
                else { hint(record.status == .ready ? "Đã tải — xem trong Thư viện → Tải xuống." : record.error ?? "Tải chưa hoàn tất.") }
            }
            menuAction("Chụp khung hình",symbol:"camera",action:screenshot)
            menuAction("Chia sẻ",symbol:"square.and.arrow.up",action:share)
            menuAction("Thu nhỏ",symbol:"pip",id:"player.minimize") { playback.minimize() }
            if presentation.pipPossible { menuAction("Picture in Picture",symbol:"pip.enter") { presentation.startPiP(); close() } }
            Divider().padding(.vertical,8)
            Text("Bỏ qua mở đầu").font(.subheadline.bold())
            Text("Tự đặt theo phim · \(Int(playback.introSkipSeconds)) giây").font(.caption).foregroundStyle(.white.opacity(0.6))
            Slider(value:$playback.introSkipSeconds,in:0...300,step:5).accessibilityLabel("Số giây bỏ qua mở đầu")
            Text("Âm lượng thiết bị").font(.subheadline.bold()).padding(.top,4)
            PlayerSystemVolume().frame(height:30)
            Text("Âm lượng video").font(.caption).foregroundStyle(.white.opacity(0.6))
            Slider(value:$playback.volume,in:0...1).accessibilityLabel("Âm lượng video")
            Text("Độ sáng").font(.subheadline.bold()).padding(.top,4)
            Slider(value:Binding(get:{ presentation.brightness },set:{ presentation.setBrightness($0) }),in:0...1).accessibilityLabel("Độ sáng")
            Divider().padding(.vertical,8)
            menuAction("Đóng player",symbol:"xmark",id:"player.close") { playback.stop() }
        }
    }
}
