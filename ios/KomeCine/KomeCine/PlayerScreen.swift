import SwiftUI
import AVKit

struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackCoordinator
    @State private var showEpisodes = false
    @State private var controlsLocked = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let landscape = geometry.size.width > geometry.size.height
                Group {
                    if landscape {
                        landscapePlayer
                    } else {
                        portraitPlayer
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .toolbar(landscape ? .hidden : .visible, for: .navigationBar)
            }
            .navigationTitle("Đang phát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Thu nhỏ") { playback.minimize() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { playback.stop() } }
            }
            .sheet(isPresented: $showEpisodes) {
                NavigationStack {
                    List {
                        ForEach(Array(Set(playback.sources.map(\.server))).sorted(), id: \.self) { server in
                            Section(server) {
                                ForEach(playback.sources.filter { $0.server == server }) { item in
                                    Button(item.name.isEmpty ? item.slug : item.name) {
                                        playback.change(to: item)
                                        showEpisodes = false
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Chọn tập")
                    .toolbar { Button("Xong") { showEpisodes = false } }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(.dark)
    }

    private var video: some View {
        Group {
            if let player = playback.player {
                SystemPlayer(player: player).allowsHitTesting(!controlsLocked)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.black)
    }

    private var lockButton: some View {
        Button { controlsLocked.toggle() } label: {
            Image(systemName: controlsLocked ? "lock.fill" : "lock.open")
                .padding(10).background(.black.opacity(0.65), in: Circle())
        }
        .accessibilityLabel(controlsLocked ? "Mở khóa player" : "Khóa player")
    }

    private var serverMenu: some View {
        Menu {
            ForEach(Array(Set(playback.sources.map(\.server))).sorted(), id: \.self) { server in
                Button(server) {
                    if let source = playback.source,
                       let match = playback.sources.first(where: { $0.server == server && $0.slug == source.slug }) {
                        playback.change(to: match)
                    } else if let first = playback.sources.first(where: { $0.server == server }) {
                        playback.change(to: first)
                    }
                }
            }
        } label: { Label("Server", systemImage: "rectangle.stack") }
    }

    private var portraitPlayer: some View {
        VStack(alignment: .leading, spacing: 20) {
            video
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .topTrailing) { lockButton.padding(10) }
            if let movie = playback.movie, let source = playback.source {
                VStack(alignment: .leading, spacing: 12) {
                    Text(movie.name).font(.title2.bold())
                    Text("\(source.server) · \(source.name)").foregroundStyle(.secondary)
                    HStack {
                        Button { showEpisodes = true } label: { Label("Chọn tập", systemImage: "square.stack") }
                        serverMenu
                    }.buttonStyle(.bordered)
                    if playback.countdown > 0 {
                        HStack {
                            Text("Tập tiếp theo sau \(playback.countdown) giây").font(.subheadline)
                            Spacer()
                            Button("Hủy") { playback.cancelNext() }
                        }
                    }
                }.padding(.horizontal, 20)
            }
            Spacer()
        }
    }

    private var landscapePlayer: some View {
        ZStack(alignment: .top) {
            video.ignoresSafeArea()
            VStack {
                HStack(spacing: 12) {
                    Button("Thu nhỏ") { playback.minimize() }
                    Spacer()
                    Button { showEpisodes = true } label: { Image(systemName: "square.stack") }
                        .accessibilityLabel("Chọn tập")
                    serverMenu.labelStyle(.iconOnly).accessibilityLabel("Server")
                    lockButton
                    Button("Đóng") { playback.stop() }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                if playback.countdown > 0 {
                    HStack {
                        Text("Tập tiếp theo sau \(playback.countdown) giây")
                        Button("Hủy") { playback.cancelNext() }
                    }
                    .padding(8).background(.black.opacity(0.75), in: Capsule())
                }
                Spacer()
            }
        }
    }
}

struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
}
