import SwiftUI
import AVKit
import MediaPlayer
import Combine

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    let gestures = PlayerGestures()
    override init(frame: CGRect) {
        super.init(frame:frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        gestures.install(on:self)
        isAccessibilityElement = true; accessibilityIdentifier = "Video"; accessibilityLabel = "Video"
        accessibilityTraits = .allowsDirectInteraction
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor final class PlayerPresentation: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var pipPossible = false
    @Published private(set) var pipActive = false
    @Published var brightness = Double(UIScreen.main.brightness)
    private var originalBrightness: CGFloat?
    private var possibleObservation: NSKeyValueObservation?
    private var pip: AVPictureInPictureController?
    lazy var surface = PlayerLayerView(frame:.zero)
    var onPiPChange: (Bool) -> Void = { _ in }
    var onRestore: () -> Void = {}

    func mount(in container: UIView, player: AVPlayer?, actions: PlayerSurfaceActions) {
        if surface.superview !== container {
            surface.removeFromSuperview(); container.addSubview(surface)
            surface.frame = container.bounds; surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        surface.gestures.actions = actions
        if surface.playerLayer.player !== player { surface.playerLayer.player = player }
        if pip == nil, AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer:surface.playerLayer)
            pip?.delegate = self; pip?.canStartPictureInPictureAutomaticallyFromInline = true
            possibleObservation = pip?.observe(\.isPictureInPicturePossible, options:[.initial, .new]) { [weak self] controller, _ in
                Task { @MainActor [weak self] in self?.pipPossible = controller.isPictureInPicturePossible }
            }
        }
    }
    func startPiP() { if pipPossible { pip?.startPictureInPicture() } }
    func stopPiP() { pip?.stopPictureInPicture() }
    func setLandscape(_ landscape: Bool) {
        guard let scene = surface.window?.windowScene ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations:landscape ? .landscapeRight : .portrait))
    }
    func setBrightness(_ value: Double) {
        if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
        brightness = min(1, max(0, value)); UIScreen.main.brightness = CGFloat(brightness)
    }
    func restoreBrightness() {
        if let originalBrightness { UIScreen.main.brightness = originalBrightness; brightness = Double(originalBrightness) }
        originalBrightness = nil
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { pipActive = true; onPiPChange(true) }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { pipActive = false; onPiPChange(false) }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { onRestore(); completionHandler(true) }
}

struct PlayerSurface: UIViewRepresentable {
    let presentation: PlayerPresentation
    let player: AVPlayer?
    var actions = PlayerSurfaceActions()
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .black
        presentation.mount(in:view, player:player, actions:actions)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { presentation.mount(in:view, player:player, actions:actions) }
    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        for case let surface as PlayerLayerView in view.subviews { surface.gestures.actions = PlayerSurfaceActions(); surface.removeFromSuperview() }
    }
}

struct PlayerAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.tintColor = .white; view.activeTintColor = .systemOrange; view.prioritizesVideoDevices = true
        view.accessibilityLabel = "AirPlay"; return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

struct PlayerSystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(); view.tintColor = .white
        view.accessibilityLabel = "Âm lượng thiết bị"; return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

struct PlayerShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems:items, applicationActivities:nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
