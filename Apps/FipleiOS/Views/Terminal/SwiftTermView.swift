import SwiftUI
import SwiftTerm
import FipleKit

/// Bridges SwiftTerm's `TerminalView` to a ``TerminalSession``.
///
/// SwiftTerm owns the xterm emulation and rendering; this view wires its two
/// directions to the session: bytes the user types go to the Mac's shell, and
/// shell output the session delivers is fed into the emulator. Size changes are
/// reported so the pty reflows. Recreated (via `.id(session.generation)`) on each
/// reconnect, so a resumed session's replayed scrollback redraws a clean screen.
struct SwiftTermView: UIViewRepresentable {
    let session: TerminalSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator
        terminal.backgroundColor = .black
        context.coordinator.attach(to: terminal)
        return terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Receives shell output from the session and forwards keystrokes back.
    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        private let session: TerminalSession
        private weak var terminal: TerminalView?

        // Pinch-to-zoom font sizing, remembered across sessions.
        private static let fontSizeKey = "com.fiple.terminal.fontSize"
        private static let minSize: CGFloat = 9
        private static let maxSize: CGFloat = 26
        private var fontSize: CGFloat = {
            let saved = UserDefaults.standard.double(forKey: fontSizeKey)
            return saved > 0 ? saved : 13
        }()
        private var pinchStartSize: CGFloat = 13

        init(session: TerminalSession) { self.session = session }

        /// Routes session output into the emulator and enables pinch-to-zoom.
        func attach(to terminal: TerminalView) {
            self.terminal = terminal
            terminal.font = Self.monospaced(fontSize)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            terminal.addGestureRecognizer(pinch)
            session.outputHandler = { [weak terminal] data in
                terminal?.feed(byteArray: ArraySlice(data))
            }
        }

        func detach() {
            session.outputHandler = nil
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let terminal else { return }
            switch gesture.state {
            case .began:
                pinchStartSize = fontSize
            case .changed, .ended:
                let target = (pinchStartSize * gesture.scale).rounded()
                let clamped = min(max(target, Self.minSize), Self.maxSize)
                if clamped != fontSize {
                    fontSize = clamped
                    terminal.font = Self.monospaced(clamped)
                }
                if gesture.state == .ended {
                    UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
                }
            default:
                break
            }
        }

        private static func monospaced(_ size: CGFloat) -> UIFont {
            UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }

        // MARK: TerminalViewDelegate
        // SwiftTerm's protocol is nonisolated; these witnesses only touch the
        // session (main-actor safe via its own isolation) — kept nonisolated to
        // satisfy the protocol, hopping onto the main actor to call it.

        nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Data(data)
            Task { @MainActor in session.send(bytes) }
        }

        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in session.resize(cols: newCols, rows: newRows) }
        }

        nonisolated func scrolled(source: TerminalView, position: Double) {}
        nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        nonisolated func clipboardCopy(source: TerminalView, content: Data) {}
        nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        nonisolated func bell(source: TerminalView) {}
        nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}
