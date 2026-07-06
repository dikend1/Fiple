import SwiftUI
import FipleKit

/// Full-screen terminal on the phone. Owns a ``TerminalSession`` that connects,
/// authenticates, and — crucially on iOS — resumes the same Mac shell when the
/// app returns from the background (the OS kills the socket within seconds of
/// backgrounding).
struct TerminalScreen: View {
    let host: String
    let port: UInt16
    let pairingToken: String
    let masterPassword: String

    @State private var session: TerminalSession?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                content(for: session)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            guard session == nil else { return }
            let session = TerminalSession(
                host: host, port: port, token: pairingToken, password: masterPassword
            )
            self.session = session
            await session.connect()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the foreground: reconnect and resume the shell.
            if phase == .active { Task { await session?.reconnectIfNeeded() } }
        }
        .onDisappear { session?.close() }
    }

    @ViewBuilder
    private func content(for session: TerminalSession) -> some View {
        switch session.phase {
        case .connecting, .authenticating:
            ProgressView(session.phase == .connecting ? "Connecting…" : "Authenticating…")
                .tint(.white).foregroundStyle(.white)
        case .ready:
            VStack(spacing: 0) {
                // A fresh emulator per connection redraws the replayed scrollback
                // cleanly instead of appending it to stale content.
                SwiftTermView(session: session).id(session.generation)
                TerminalAccessoryBar(session: session)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        case let .failed(message):
            failureView(session, message: message)
        case .ended:
            statusMessage("Session paused", "Reopen to resume your shell.", systemImage: "moon.zzz")
        }
    }

    private func failureView(_ session: TerminalSession, message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Couldn’t open terminal").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            Button("Try Again") {
                // A wrong password is usually a stale saved one — forget it so the
                // next attempt asks fresh — then return to Home to re-enter.
                if session.lastAuthFailReason == .badPassword {
                    TerminalCredentialStore.clear()
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .foregroundStyle(.white)
        .padding()
    }

    private func statusMessage(_ title: String, _ detail: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        }
        .foregroundStyle(.white)
    }
}

/// A keyboard accessory row for keys a soft keyboard lacks — Esc, Tab, arrows,
/// and Ctrl-C, the ones you actually need in a shell.
private struct TerminalAccessoryBar: View {
    let session: TerminalSession

    var body: some View {
        HStack(spacing: 8) {
            key("esc") { session.send(Data([0x1b])) }
            key("tab") { session.send(Data([0x09])) }
            key("⌃C") { session.send(Data([0x03])) }
            key("↑") { session.send(Data([0x1b, 0x5b, 0x41])) }
            key("↓") { session.send(Data([0x1b, 0x5b, 0x42])) }
            key("←") { session.send(Data([0x1b, 0x5b, 0x44])) }
            key("→") { session.send(Data([0x1b, 0x5b, 0x43])) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 40)
                .padding(.vertical, 6)
                .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
        }
    }
}
