import UIKit

struct PlayerSurfaceActions {
    var tap: () -> Void = {}
    var skip: (Double) -> Void = { _ in }
    var boost: (Bool) -> Void = { _ in }
    var scrub: (Double, Bool) -> Void = { _, _ in }
    var adjust: (Bool, Double, Bool) -> Void = { _, _, _ in }
    var locked = false
}

final class PlayerGestures: NSObject, UIGestureRecognizerDelegate {
    var actions = PlayerSurfaceActions()
    private var panMode: Bool?
    private var verticalIsBrightness = false
    private var beganPan = false
    private var initialPoint = CGPoint.zero
    let single = UITapGestureRecognizer()
    let double = UITapGestureRecognizer()
    let hold = UILongPressGestureRecognizer()
    let pan = UIPanGestureRecognizer()

    func install(on view: UIView) {
        single.addTarget(self, action:#selector(tapped))
        double.numberOfTapsRequired = 2; double.addTarget(self, action:#selector(doubleTapped))
        single.require(toFail:double)
        hold.minimumPressDuration = 0.45; hold.addTarget(self, action:#selector(held))
        pan.addTarget(self, action:#selector(panned))
        for recognizer in [single, double, hold, pan] { recognizer.delegate = self; view.addGestureRecognizer(recognizer) }
    }
    @objc private func tapped() { actions.tap() }
    @objc private func doubleTapped() {
        guard !actions.locked, let view = double.view else { return }
        actions.skip(double.location(in:view).x < view.bounds.midX ? -10 : 10)
    }
    @objc private func held() {
        guard !actions.locked else { return }
        if hold.state == .began { actions.boost(true) }
        if [.ended, .cancelled, .failed].contains(hold.state) { actions.boost(false) }
    }
    @objc private func panned() {
        guard !actions.locked, let view = pan.view else { return }
        let delta = pan.translation(in:view)
        switch pan.state {
        case .began:
            panMode = nil; beganPan = false; initialPoint = pan.location(in:view)
        case .changed:
            if panMode == nil, max(abs(delta.x), abs(delta.y)) > 8 {
                panMode = abs(delta.x) > abs(delta.y); verticalIsBrightness = initialPoint.x < view.bounds.midX
            }
            guard let horizontal = panMode else { return }
            beganPan = true
            if horizontal { actions.scrub(Double(delta.x / max(1, view.bounds.width)), false) }
            else { actions.adjust(verticalIsBrightness, Double(-delta.y / max(1, view.bounds.height)), false) }
        case .ended, .cancelled, .failed:
            guard beganPan, let horizontal = panMode else { return }
            if horizontal { actions.scrub(Double(delta.x / max(1, view.bounds.width)), true) }
            else { actions.adjust(verticalIsBrightness, Double(-delta.y / max(1, view.bounds.height)), true) }
            panMode = nil; beganPan = false
        default: break
        }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if UIAccessibility.isVoiceOverRunning { return false }
        return gestureRecognizer === single || !actions.locked
    }
}
