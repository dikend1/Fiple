import SwiftUI
import SwiftTerm
import FipleKit

/// Bridges SwiftTerm's `TerminalView` to a ``TerminalClient``.
///
/// SwiftTerm owns the xterm emulation and rendering; this view wires its two
/// directions to the encrypted channel: bytes the user types are forwarded to
/// the Mac's pty, and shell output from the channel is fed back into the
/// emulator. Size changes are reported so the pty reflows.
struct SwiftTermView: UIViewRepresentable {
    let client: TerminalClient

    func makeCoordinator() -> Coordinator { Coordinator(client: client) }

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

    /// Owns the client→terminal pump and forwards terminal→client events.
    /// Main-actor isolated: SwiftTerm drives the delegate on the main thread and
    /// all `TerminalView` mutation must happen there.
    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        private let client: TerminalClient
        private weak var terminal: TerminalView?
        private var pumpTask: Task<Void, Never>?

        init(client: TerminalClient) { self.client = client }

        /// Starts draining channel output into the emulator once the view exists.
        func attach(to terminal: TerminalView) {
            self.terminal = terminal
            pumpTask = Task { [weak self] in
                guard let self else { return }
                for await event in self.client.events {
                    switch event {
                    case let .output(data):
                        self.terminal?.feed(byteArray: ArraySlice(data))
                    case let .ended(code):
                        let note = "\r\n[session ended\(code.map { " (exit \($0))" } ?? "")]\r\n"
                        self.terminal?.feed(text: note)
                    case .authenticated, .authFailed:
                        break // handled by TerminalScreen
                    }
                }
            }
        }

        func detach() {
            pumpTask?.cancel()
            pumpTask = nil
        }

        // MARK: TerminalViewDelegate
        // SwiftTerm's protocol is nonisolated; these witnesses only touch the
        // Sendable `client`, so they stay nonisolated and hop nowhere.

        /// User typed something → forward the bytes to the Mac's shell.
        nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
            client.send(Data(data))
        }

        /// The visible grid changed → tell the pty so full-screen apps reflow.
        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            client.resize(cols: newCols, rows: newRows)
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
