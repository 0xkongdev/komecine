import SwiftUI
import AVKit

struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackCoordinator
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var showEpisodes = false
    @State private var showServers = false
    @State private var controlsLocked = false
    @State private var controlsVisible = true
    @State private var interactionID = UUID()
    @State private var fullscreenLayoutIsLandscape: Bool?

    private var servers: [String] { Array(Set(playback.sources.map(\.server))).sorted() }
    private var showActions: Bool { controlsVisible && !controlsLocked }

    var body: some View {
        GeometryReader { geometry in
            // Keep the embedded controller mounted while AVKit presents fullscreen.
            let landscape = fullscreenLayoutIsLandscape ?? (geometry.size.width > geometry.size.height)
            Group {
                if landscape {
                    landscapePlayer
                } else {
                    portraitPlayer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!controlsVisible || controlsLocked)
        .task(id: interactionID) {
            guard controlsVisible, !showEpisodes, !showServers, !voiceOverEnabled else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
        }
        .onChange(of: showEpisodes) { _, _ in revealControls() }
        .onChange(of: showServers) { _, _ in revealControls() }
        .onChange(of: voiceOverEnabled) { _, _ in revealControls() }
        .onChange(of: playback.source?.id) { _, _ in revealControls() }
        .sheet(isPresented: $showEpisodes) { episodePicker }
        .confirmationDialog("Chọn server", isPresented: $showServers, titleVisibility: .visible) {
            ForEach(servers, id: \.self) { server in
                Button(server == playback.source?.server ? "\(server) ✓" : server) { changeServer(to: server) }
            }
        }
    }

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
        interactionID = UUID()
    }

    private func toggleControls() {
        guard !voiceOverEnabled else { revealControls(); return }
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        interactionID = UUID()
    }

    private var video: some View {
        Group {
            if let player = playback.player {
                SystemPlayer(player: player, controlsLocked: controlsLocked, onVideoTap: toggleControls,
                             onFullscreenLayoutChange: { fullscreenLayoutIsLandscape = $0 })
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.black)
    }

    private func iconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(title)
    }

    private var lockButton: some View {
        iconButton(controlsLocked ? "Mở khóa player" : "Khóa player", symbol: controlsLocked ? "lock.fill" : "lock.open") {
            controlsLocked.toggle()
            revealControls()
        }
    }

    private var playerHeader: some View {
        HStack(spacing: 12) {
            if !controlsLocked {
                iconButton("Thu nhỏ", symbol: "chevron.down") { playback.minimize() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.movie?.name ?? "Đang phát")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let source = playback.source {
                        Text("\(source.server) · \(source.name)")
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                iconButton("Chọn tập", symbol: "square.stack") { showEpisodes = true }
                iconButton("Server", symbol: "server.rack") { showServers = true }
            } else {
                Spacer()
            }
            lockButton
            if !controlsLocked {
                iconButton("Đóng", symbol: "xmark") { playback.stop() }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background {
            if !controlsLocked {
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    private var portraitPlayer: some View {
        VStack(spacing: 0) {
            // Reserve the header's height so hiding it never moves the video.
            HStack {
                iconButton("Thu nhỏ", symbol: "chevron.down") { playback.minimize() }
                Spacer()
                Text("ĐANG PHÁT").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                iconButton("Đóng", symbol: "xmark") { playback.stop() }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .opacity(showActions ? 1 : 0)
            .allowsHitTesting(showActions)
            .accessibilityHidden(!showActions)

            video
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if controlsVisible { lockButton.padding(12).transition(.opacity) }
                }

            if let movie = playback.movie, let source = playback.source {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(movie.name).font(.title2.bold())
                        Text("\(source.server) · \(source.name)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !controlsLocked {
                        HStack(spacing: 12) {
                            Button { showEpisodes = true } label: {
                                Label("Chọn tập", systemImage: "square.stack")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                            Button { showServers = true } label: {
                                Label("Server", systemImage: "server.rack")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .font(.subheadline.weight(.semibold)).buttonStyle(.plain)
                    }
                    if playback.countdown > 0 { nextEpisodePrompt }
                }
                .padding(24)
            }
            Spacer(minLength: 0)
        }
    }

    private var landscapePlayer: some View {
        ZStack(alignment: .top) {
            video.ignoresSafeArea()
            if controlsVisible { playerHeader.transition(.opacity) }
            if playback.countdown > 0 {
                VStack { Spacer(); nextEpisodePrompt.padding(.bottom, 85) }
                    .padding(.horizontal, 24)
            }
        }
    }

    private var nextEpisodePrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle").foregroundStyle(Color.accentColor)
            Text("Tập tiếp theo sau \(playback.countdown) giây").font(.subheadline)
            Spacer(minLength: 0)
            Button("Hủy") { playback.cancelNext(); revealControls() }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var episodePicker: some View {
        NavigationStack {
            List {
                ForEach(servers, id: \.self) { server in
                    Section(server) {
                        ForEach(playback.sources.filter { $0.server == server }) { item in
                            Button {
                                playback.change(to: item)
                                showEpisodes = false
                            } label: {
                                HStack {
                                    Label(item.name.isEmpty ? item.slug : item.name, systemImage: "play.circle")
                                    Spacer()
                                    if item.id == playback.source?.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                    }
                                }.frame(minHeight: 32)
                            }
                            .foregroundStyle(item.id == playback.source?.id ? Color.accentColor : .primary)
                        }
                    }
                }
            }
            .navigationTitle("Chọn tập")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { showEpisodes = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func changeServer(to server: String) {
        let match = playback.sources.first { $0.server == server && $0.slug == playback.source?.slug }
        if let next = match ?? playback.sources.first(where: { $0.server == server }) { playback.change(to: next) }
    }
}

struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var controlsLocked = false
    var onVideoTap: () -> Void = {}
    var onFullscreenLayoutChange: (Bool?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoTap: onVideoTap, onFullscreenLayoutChange: onFullscreenLayoutChange)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = !controlsLocked
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.videoTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        controller.view.addGestureRecognizer(tap)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = !controlsLocked
        context.coordinator.onVideoTap = onVideoTap
        context.coordinator.onFullscreenLayoutChange = onFullscreenLayoutChange
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, AVPlayerViewControllerDelegate {
        var onVideoTap: () -> Void
        var onFullscreenLayoutChange: (Bool?) -> Void
        private var orientationBeforeFullscreen: UIInterfaceOrientation = .portrait
        private weak var fullscreenScene: UIWindowScene?

        init(onVideoTap: @escaping () -> Void, onFullscreenLayoutChange: @escaping (Bool?) -> Void) {
            self.onVideoTap = onVideoTap
            self.onFullscreenLayoutChange = onFullscreenLayoutChange
        }
        @objc func videoTapped() { onVideoTap() }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            guard let scene = playerViewController.view.window?.windowScene else { return }
            fullscreenScene = scene
            orientationBeforeFullscreen = scene.interfaceOrientation
            onFullscreenLayoutChange(orientationBeforeFullscreen.isLandscape)
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                guard !context.isCancelled else {
                    self.onFullscreenLayoutChange(nil)
                    return
                }
                self.requestOrientation(.landscape, in: scene)
            }
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self, !context.isCancelled else { return }
                let orientation: UIInterfaceOrientationMask
                switch self.orientationBeforeFullscreen {
                case .landscapeLeft: orientation = .landscapeLeft
                case .landscapeRight: orientation = .landscapeRight
                case .portraitUpsideDown: orientation = .portraitUpsideDown
                default: orientation = .portrait
                }
                if let scene = self.fullscreenScene { self.requestOrientation(orientation, in: scene) }
                self.onFullscreenLayoutChange(nil)
                self.fullscreenScene = nil
            }
        }

        private func requestOrientation(_ orientations: UIInterfaceOrientationMask, in scene: UIWindowScene) {
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Native transport buttons and scrubbing keep their normal touch handling.
            var view = touch.view
            while let current = view {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
        }
    }
}
