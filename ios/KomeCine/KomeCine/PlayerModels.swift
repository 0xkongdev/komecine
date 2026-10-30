import Foundation

enum PlayerPanel: String, CaseIterable { case speed, quality, captions, episodes, servers, more }

struct PlayerInteractionState {
    private(set) var visible = true
    private(set) var locked = false
    private(set) var panel: PlayerPanel?
    var isInteracting = false
    mutating func reveal() { visible = true }
    mutating func toggle() { visible.toggle() }
    mutating func open(_ value: PlayerPanel) { guard !locked else { return }; panel = value; visible = true }
    mutating func closePanel() { panel = nil; visible = true }
    mutating func toggleLock() { locked.toggle(); panel = nil; visible = true }
    mutating func autoHide(isPlaying: Bool, voiceOver: Bool) {
        guard isPlaying, !voiceOver, panel == nil, !isInteracting else { return }
        visible = false
    }
}

enum PlaybackMath {
    static func clamp(_ seconds: Double, duration: Double) -> Double? {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return nil }
        return min(max(0, seconds), duration)
    }
    static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(seconds, 3_600_000))) : 0
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct VideoQuality: Identifiable, Equatable {
    let height: Int
    let width: Int
    let bandwidth: Double
    let url: URL
    var id: Int { height }
    var title: String { height >= 2160 ? "4K" : "\(height)p" }
}

struct HLSTextTrack: Identifiable, Equatable {
    let name: String
    let language: String
    let url: URL
    var id: String { url.absoluteString }
}
