import SwiftUI
import AVKit

struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var library: LocalLibrary
    @EnvironmentObject private var downloads: OfflineDownloads
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var interaction = PlayerInteractionState()
    @State private var timerID = UUID()
    @State private var feedback: String?
    @State private var feedbackID = UUID()
    @State private var previewPosition: Double?
    @State private var dragOrigin: Double?
    @State private var adjustOrigin: Double?
    @State private var sharing = false
    @State private var shareItems: [Any] = []
    @State private var message: String?
    @State private var capturing = false

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack(alignment:.top) {
                Color.black
                VStack(spacing:0) {
                    video(landscape:landscape, safe:geometry.safeAreaInsets)
                        .frame(width:geometry.size.width,height:landscape ? geometry.size.height : geometry.size.width * 9 / 16)
                    if !landscape { portraitDetails.allowsHitTesting(!interaction.locked).accessibilityHidden(interaction.locked) }
                }
                if let panel = interaction.panel {
                    Color.black.opacity(0.22).onTapGesture { closePanel() }.accessibilityLabel("Đóng bảng").accessibilityAddTraits(.isButton)
                    HStack {
                        Spacer(minLength:0)
                        PlayerPanels(panel:panel,playback:playback,presentation:playback.presentation,downloads:downloads,favorite:isFavorite,
                                     close:closePanel,toggleFavorite:toggleFavorite,screenshot:capture,share:share,download:download)
                            .frame(width:min(360,geometry.size.width * 0.88))
                            .padding(.top,landscape ? 12 : geometry.safeAreaInsets.top + 8)
                            .padding(.bottom,max(12,geometry.safeAreaInsets.bottom))
                            .padding(.trailing,max(12,geometry.safeAreaInsets.trailing))
                    }.transition(.move(edge:.trailing).combined(with:.opacity))
                }
            }
        }
        .background(.black).preferredColorScheme(.dark)
        .statusBarHidden(true).ignoresSafeArea(.container,edges:.bottom)
        .task(id:timerID) {
            guard interaction.visible, interaction.panel == nil, !voiceOver, !interaction.isInteracting else { return }
            do { try await Task.sleep(for:.seconds(3)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration:0.2)) { interaction.autoHide(isPlaying:playback.isPlaying,voiceOver:voiceOver) }
        }
        .task(id:feedbackID) {
            guard feedback != nil else { return }
            do { try await Task.sleep(for:.seconds(1.2)) } catch { return }
            guard !Task.isCancelled, !interaction.isInteracting else { return }; feedback = nil
        }
        .onAppear { interaction = PlayerInteractionState(); timerID = UUID() }
        .onChange(of:playback.isPlaying) { _, _ in reveal() }
        .onChange(of:playback.source?.id) { _, _ in reveal() }
        .onChange(of:voiceOver) { _, _ in reveal() }
        .onDisappear { playback.endBoost(); playback.presentation.restoreBrightness() }
        .sheet(isPresented:$sharing) { PlayerShareSheet(items:shareItems) }
        .alert("KomeCine",isPresented:Binding(get:{ message != nil },set:{ if !$0 { message = nil } })) { Button("Đóng",role:.cancel) { message = nil } } message: { Text(message ?? "") }
    }

    private var isFavorite: Bool { library.favorites.contains { $0.id == playback.movie?.id } }
    private func reveal() { interaction.reveal(); timerID = UUID() }
    private func closePanel() { withAnimation(.easeInOut(duration:0.2)) { interaction.closePanel() }; timerID = UUID() }
    private func open(_ panel: PlayerPanel) { withAnimation(.easeInOut(duration:0.2)) { interaction.open(panel) }; timerID = UUID() }
    private func notify(_ text: String) { feedback = text; feedbackID = UUID() }
    private func toggleFavorite() { if let movie = playback.movie { library.toggleFavorite(movie); notify(isFavorite ? "Đã thêm vào danh sách xem" : "Đã bỏ khỏi danh sách xem") } }
    private func download() {
        guard let movie = playback.movie, let source = playback.source else { return }
        downloads.download(movie:movie,source:source)
        notify("Đã thêm vào Tải xuống")
    }
    private func share() {
        guard let movie = playback.movie else { return }
        shareItems = [movie.name]
        if let link = playback.source?.url, let url = URL(string:link), !url.isFileURL { shareItems.append(url) }
        sharing = true
    }
    private func capture() {
        guard !capturing else { return }; capturing = true
        let id = playback.source?.id
        Task { @MainActor in
            defer { capturing = false }
            do {
                let image = try await playback.captureFrame()
                guard playback.source?.id == id else { return }
                shareItems = [image]; sharing = true
            } catch { message = "Nguồn phim này chưa cho phép lấy khung hình ở thời điểm hiện tại." }
        }
    }

    private var actions: PlayerSurfaceActions {
        PlayerSurfaceActions(tap:{
            if voiceOver { reveal() } else { withAnimation(.easeInOut(duration:0.2)) { interaction.toggle() }; timerID = UUID() }
        },skip:{ amount in playback.skip(amount); notify(amount > 0 ? "+10 giây" : "−10 giây"); reveal() },boost:{ active in
            interaction.isInteracting = active
            if active { playback.beginBoost(); notify("Đang phát 2×") }
            else { playback.endBoost(); feedback = nil }
            reveal()
        },scrub:{ fraction, ended in
            if dragOrigin == nil { dragOrigin = playback.position }
            interaction.isInteracting = !ended
            let time = (dragOrigin ?? 0) + fraction * max(60,min(600,playback.duration * 0.5))
            previewPosition = PlaybackMath.clamp(time,duration:playback.duration)
            if let previewPosition { notify(PlaybackMath.time(previewPosition)) }
            if ended { if let previewPosition { playback.seek(to:previewPosition) }; previewPosition = nil; dragOrigin = nil }
            reveal()
        },adjust:{ brightness, amount, ended in
            interaction.isInteracting = !ended
            if adjustOrigin == nil { adjustOrigin = brightness ? playback.presentation.brightness : Double(playback.volume) }
            let value = min(1,max(0,(adjustOrigin ?? 0) + amount))
            if brightness { playback.presentation.setBrightness(value) } else { playback.volume = Float(value) }
            notify("\(brightness ? "Độ sáng" : "Âm lượng video") \(Int(value * 100))%")
            if ended { adjustOrigin = nil }
            reveal()
        },locked:interaction.locked)
    }

    private func video(landscape: Bool, safe: EdgeInsets) -> some View {
        ZStack {
            PlayerSurface(presentation:playback.presentation,player:playback.player,actions:actions).ignoresSafeArea(.container,edges:.horizontal)
            PlayerCaptionOverlay(subtitles:playback.subtitles,size:playback.captionSize)
                .padding(.horizontal,landscape ? 90 : 22)
                .padding(.bottom,interaction.visible && !interaction.locked ? (landscape ? 104 : 62) : 18)
                .allowsHitTesting(false)
            if interaction.visible {
                VStack(spacing:0) {
                    if !interaction.locked { header(landscape:landscape) }
                    Spacer(minLength:0)
                    HStack {
                        icon(interaction.locked ? "Mở khóa player" : "Khóa player",symbol:interaction.locked ? "lock.fill" : "lock.open",id:"player.lock") { interaction.toggleLock(); timerID = UUID() }
                        Spacer()
                        if !interaction.locked, landscape {
                            VStack(spacing:16) {
                                icon("Chụp khung hình",symbol:"camera",id:"player.capture",action:capture)
                                icon(isFavorite ? "Bỏ yêu thích" : "Yêu thích",symbol:isFavorite ? "heart.fill" : "heart",id:"player.favorite",action:toggleFavorite)
                            }
                        }
                    }
                    Spacer(minLength:0)
                    if !interaction.locked { transport(landscape:landscape) }
                }
                .padding(.horizontal,12)
                .padding(.top,8)
                .padding(.bottom,landscape ? max(12,safe.bottom) : 6)
                .background {
                    if !interaction.locked {
                        VStack { LinearGradient(colors:[.black.opacity(0.65),.clear],startPoint:.top,endPoint:.bottom).frame(height:90); Spacer(minLength:0); LinearGradient(colors:[.clear,.black.opacity(0.8)],startPoint:.top,endPoint:.bottom).frame(height:110) }.allowsHitTesting(false)
                    }
                }
                .transition(.opacity)
            }
            if !interaction.locked, interaction.panel == nil {
                if let error = playback.error {
                    VStack(spacing:12) {
                        Text(error).font(.subheadline).multilineTextAlignment(.center)
                        HStack { Button("Thử lại") { playback.retry(); reveal() }; Button("Đổi server") { open(.servers) } }.buttonStyle(.bordered)
                    }.padding(20).background(.black.opacity(0.75),in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,60)
                } else if playback.isBuffering || capturing { ProgressView().tint(.white).scaleEffect(1.3).allowsHitTesting(false) }
                else if interaction.visible && !playback.isPlaying {
                    Button { playback.togglePlayback(); reveal() } label: { Image(systemName:"play.fill").font(.system(size:landscape ? 60 : 40)).frame(width:90,height:90) }
                        .buttonStyle(.plain).accessibilityLabel("Phát video").accessibilityIdentifier("player.centerPlay")
                }
            }
            if let feedback {
                Text(feedback).font(.headline.monospacedDigit()).padding(.horizontal,20).padding(.vertical,12)
                    .background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:10)).allowsHitTesting(false)
            }
            if playback.countdown > 0 {
                VStack { Spacer(); HStack { Text("Tập tiếp theo sau \(playback.countdown) giây"); Button("Hủy") { playback.cancelNext() } }.font(.subheadline).padding(14).background(.black.opacity(0.85),in:RoundedRectangle(cornerRadius:10)).padding(.bottom,100) }
            } else if playback.introSkipSeconds > playback.position, playback.position < playback.introSkipSeconds, !interaction.locked {
                VStack { Spacer(); HStack { Spacer(); Button("Bỏ qua mở đầu") { playback.seek(to:playback.introSkipSeconds); reveal() }.font(.caption.bold()).padding(12).background(.black.opacity(0.6),in:RoundedRectangle(cornerRadius:6)) }.padding(.trailing,65).padding(.bottom,100) }
            }
        }.foregroundStyle(.white).background(.black)
    }

    private func header(landscape: Bool) -> some View {
        HStack(spacing:8) {
            icon(landscape ? "Trở về màn hình dọc" : "Thu nhỏ",symbol:"chevron.left",id:"player.back") { if landscape { playback.presentation.setLandscape(false) } else { playback.minimize() } }
            Text([playback.source?.name,playback.movie?.name].compactMap { $0 }.joined(separator:" · ")).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength:0)
            if landscape {
                Text("KomeCine").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.75)).padding(.trailing,8)
            }
            PlayerAirPlayButton().frame(width:44,height:44)
            icon("Tùy chọn",symbol:"ellipsis",id:"player.more") { open(.more) }
        }
    }
    private func transport(landscape: Bool) -> some View {
        VStack(spacing:landscape ? 8 : 0) {
            if landscape {
                HStack(spacing:12) { clock; scrubber }
                HStack(spacing:6) {
                    playButton
                    icon("Tập tiếp theo",symbol:"forward.end.fill",id:"player.next") { if let next = playback.nextSource { playback.change(to:next); reveal() } }.disabled(playback.nextSource == nil).opacity(playback.nextSource == nil ? 0.35 : 1)
                    Spacer(minLength:8)
                    textControl("Tốc độ \(speedTitle)",text:playback.selectedSpeed == 1 ? "SPEED" : speedTitle,id:"player.speed") { open(.speed) }
                    textControl("Chất lượng",text:playback.selectedQuality.map { "\($0)p" } ?? "AUTO",id:"player.quality") { open(.quality) }
                    textControl("Phụ đề",text:"CC",id:"player.captions") { open(.captions) }
                    icon("Chọn tập",symbol:"rectangle.stack",id:"player.episodes") { open(.episodes) }
                    fullscreen(landscape:true)
                }
            } else {
                HStack(spacing:8) { playButton; clock; scrubber; fullscreen(landscape:false) }
            }
        }
    }
    private var speedTitle: String { String(format:"%g×",playback.selectedSpeed) }
    private var clock: some View {
        Text("\(PlaybackMath.time(previewPosition ?? playback.position)) / \(PlaybackMath.time(playback.duration))")
            .font(.system(size:12,weight:.medium,design:.monospaced)).fixedSize()
    }
    private var scrubber: some View {
        PlayerScrubber(value:Binding(get:{ previewPosition ?? min(playback.position,max(1,playback.duration)) },set:{ previewPosition = $0 }),duration:playback.duration) { editing in
            interaction.isInteracting = editing
            if !editing { if let previewPosition { playback.seek(to:previewPosition) }; previewPosition = nil }
            reveal()
        }.tint(.white).disabled(playback.duration <= 0).accessibilityLabel("Tiến trình phát").accessibilityIdentifier("player.scrubber")
    }
    private var playButton: some View {
        icon(playback.isPlaying ? "Tạm dừng" : "Phát",symbol:playback.isPlaying ? "pause.fill" : "play.fill",id:"player.play") { playback.togglePlayback(); reveal() }
    }
    private func fullscreen(landscape: Bool) -> some View {
        icon(landscape ? "Thoát toàn màn hình" : "Toàn màn hình",symbol:landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",id:"player.fullscreen") { playback.presentation.setLandscape(!landscape); reveal() }
    }
    private func icon(_ label: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:symbol).font(.system(size:21,weight:.medium)).frame(width:44,height:44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func textControl(_ label: String, text: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action:action) { Text(text).font(.system(size:11,weight:.bold)).padding(.horizontal,5).padding(.vertical,3).overlay { RoundedRectangle(cornerRadius:2).strokeBorder(.white,lineWidth:1.5) }.frame(minWidth:44,minHeight:44) }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func portraitAction(_ title: String, panel: PlayerPanel) -> some View {
        Button { open(panel) } label: { Text(title).frame(minHeight:44).contentShape(Rectangle()) }
    }
    private var portraitDetails: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack(spacing:14) {
                    Text(playback.movie?.name ?? "Đang phát").font(.title2.bold()).frame(maxWidth:.infinity,alignment:.leading)
                    Button(action:toggleFavorite) { Image(systemName:isFavorite ? "heart.fill" : "heart").font(.title3).frame(width:44,height:44) }.accessibilityLabel("Yêu thích")
                }
                Text("\(playback.source?.server ?? "") · \(playback.source?.name ?? "")").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing:12) {
                    portraitAction("Tốc độ \(speedTitle)",panel:.speed)
                    portraitAction("Chất lượng",panel:.quality)
                    portraitAction("Phụ đề",panel:.captions)
                    Spacer(minLength:0)
                    Button { open(.servers) } label: { Image(systemName:"server.rack").frame(width:44,height:44) }.accessibilityLabel("Server")
                }.font(.caption.weight(.semibold))
                HStack { Text("Danh sách phát").font(.headline); Spacer(); portraitAction("Chọn tập",panel:.episodes) }
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHStack(spacing:10) {
                        ForEach(playback.sources.filter { $0.server == playback.source?.server }) { episode in
                            Button { playback.change(to:episode); reveal() } label: {
                                Text(episode.name.isEmpty ? episode.slug : episode.name).font(.subheadline.weight(.semibold)).frame(minWidth:64,minHeight:46).padding(.horizontal,8)
                                    .background(playback.source?.id == episode.id ? Color.accentColor.opacity(0.18) : .white.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
                                    .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(playback.source?.id == episode.id ? Color.accentColor : .clear,lineWidth:1) }
                            }
                        }
                    }
                }
                if !playback.movieDescription.isEmpty {
                    Text("Nội dung").font(.headline)
                    Text(playback.movieDescription.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5)
                }
                HStack(spacing:24) {
                    Button(action:download) { Label("Tải xuống",systemImage:"arrow.down.circle").frame(minHeight:44).contentShape(Rectangle()) }
                    Button(action:share) { Label("Chia sẻ",systemImage:"square.and.arrow.up").frame(minHeight:44).contentShape(Rectangle()) }
                }.font(.subheadline).padding(.vertical,6)
            }.padding(20).padding(.bottom,30)
        }.background(Color(red:0.04,green:0.04,blue:0.05)).foregroundStyle(.white)
    }
}

private struct PlayerCaptionOverlay: View {
    @ObservedObject var subtitles: SubtitleController
    let size: Double
    var body: some View {
        VStack { Spacer(); VStack(spacing:4) {
            if let error = subtitles.error { Text(error).font(.caption).foregroundStyle(.white).padding(8).background(.black.opacity(0.8),in:RoundedRectangle(cornerRadius:6)) }
            if !subtitles.primaryText.isEmpty { Text(subtitles.primaryText).font(.system(size:size,weight:.semibold)).foregroundStyle(.white) }
            if !subtitles.secondaryText.isEmpty { Text(subtitles.secondaryText).font(.system(size:size * 0.85,weight:.medium)).foregroundStyle(.yellow) }
        }.multilineTextAlignment(.center).shadow(color:.black,radius:2,x:1,y:1).padding(.horizontal,6).background(.black.opacity(subtitles.primaryText.isEmpty ? 0 : 0.25),in:RoundedRectangle(cornerRadius:4)) }
    }
}
