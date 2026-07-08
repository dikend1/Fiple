import FipleKit
import SwiftUI
import UIKit

/// Installs the four global multi-touch swipe gestures over the whole app:
/// two fingers up/down → copy/paste, four fingers up/down → enter/exit
/// fullscreen. The recognizers are attached to the key **window** so they
/// observe touches everywhere; with `cancelsTouchesInView = false` they never
/// steal a tap on a tile or a one-finger scroll — those use a different finger
/// count and fall straight through.
struct GestureOverlay: UIViewRepresentable {
    /// Invoked on the main actor when a bound swipe is recognized.
    let onGesture: (GestureAction) -> Void

    func makeUIView(context: Context) -> GestureHostView {
        let view = GestureHostView()
        view.onGesture = onGesture
        return view
    }

    func updateUIView(_ uiView: GestureHostView, context: Context) {
        uiView.onGesture = onGesture
    }

    static func dismantleUIView(_ uiView: GestureHostView, coordinator: ()) {
        uiView.removeRecognizers()
    }
}

/// A transparent, touch-passthrough view that owns the window-level swipe
/// recognizers. Attaching happens in `didMoveToWindow` — the reliable moment the
/// view actually joins a window (doing it in `updateUIView` races the window
/// being `nil` on first call, so the recognizers would never install).
final class GestureHostView: UIView, UIGestureRecognizerDelegate {
    var onGesture: ((GestureAction) -> Void)?
    private var recognizers: [UISwipeGestureRecognizer] = []

    override func didMoveToWindow() {
        super.didMoveToWindow()
        removeRecognizers()
        guard let window else { return }
        let specs: [(fingers: Int, direction: UISwipeGestureRecognizer.Direction)] = [
            (2, .up), (2, .down), (4, .up), (4, .down),
        ]
        for spec in specs {
            let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.numberOfTouchesRequired = spec.fingers
            recognizer.direction = spec.direction
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            recognizers.append(recognizer)
        }
    }

    func removeRecognizers() {
        for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizers.removeAll()
    }

    @objc private func handle(_ recognizer: UISwipeGestureRecognizer) {
        let direction: SwipeDirection = recognizer.direction == .up ? .up : .down
        guard let action = GestureAction.from(
            fingers: recognizer.numberOfTouchesRequired, direction: direction
        ) else { return }
        onGesture?(action)
    }

    // Never intercept touches — hit tests fall through to the SwiftUI content
    // below; the recognizers observe touches from the window instead.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    // Without this, SwiftUI's scroll pan wins the gesture arbitration and the
    // multi-finger swipes never fire over scrollable content (most of the app).
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}
