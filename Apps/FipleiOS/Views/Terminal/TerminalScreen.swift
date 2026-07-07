import SwiftUI
import UIKit
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
    /// True when the password was typed (not from Face ID) — save it behind
    /// biometrics once it authenticates, so next time is one-tap Face ID.
    var rememberOnSuccess: Bool = false

    @State private var session: TerminalSession?
    @State private var didRemember = false
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
            session?.scenePhaseChanged(active: phase == .active)
        }
        .onChange(of: session?.phase) { _, phase in
            guard let phase else { return }
            if phase == .ready, rememberOnSuccess, !didRemember {
                // The typed password just authenticated — remember it now.
                didRemember = true
                TerminalCredentialStore.save(masterPassword)
            }
            if case .failed = phase, session?.lastAuthFailReason == .badPassword {
                // A wrong (likely stale) saved password — forget it so the next
                // open asks fresh instead of failing again.
                TerminalCredentialStore.clear()
            }
        }
        .onDisappear { session?.close() }
    }

    @ViewBuilder
    private func content(for session: TerminalSession) -> some View {
        switch session.phase {
        case .connecting, .authenticating:
            ProgressView(session.phase == .connecting ? "Connecting…" : "Authenticating…")
                .tint(.white).foregroundStyle(.white)
        case .reconnecting:
            VStack(spacing: 16) {
                ProgressView().tint(.white)
                VStack(spacing: 6) {
                    Text("Reconnecting…").font(.headline).foregroundStyle(.white)
                    Text("Waiting for your Mac. If it’s asleep, wake it — your shell is kept for you.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered).tint(.white)
            }
            .padding()
        case .ready:
            VStack(spacing: 0) {
                terminalTopBar
                // A fresh emulator per connection redraws the replayed scrollback
                // cleanly instead of appending it to stale content.
                SwiftTermView(session: session).id(session.generation)
                TerminalAccessoryBar(session: session)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        case let .failed(message):
            failureView(session, message: message)
        case .ended:
            VStack(spacing: 20) {
                Image(systemName: "moon.zzz").font(.system(size: 44)).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text("Session paused").font(.headline)
                    Text("Reopen to resume your shell.").font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
            }
            .foregroundStyle(.white).padding()
        }
    }

    /// A slim bar over the terminal with the way out — the shell keeps running on
    /// the Mac (detached), so this just closes the screen, it doesn't kill it.
    private var terminalTopBar: some View {
        HStack {
            Button { dismiss() } label: {
                Label("Done", systemImage: "chevron.down")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .tint(.white)
            Spacer()
            Text("Terminal").font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            // Balances the leading button so the title stays centered.
            Label("Done", systemImage: "chevron.down").opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black)
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

/// A keyboard accessory row for keys a soft keyboard lacks — Esc, Tab, Ctrl-C,
/// arrows — plus a one-tap Paste (copy is the native long-press → Copy menu).
/// Horizontally scrollable so nothing clips on narrow phones.
private struct TerminalAccessoryBar: View {
    let session: TerminalSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                iconKey("doc.on.clipboard") {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        session.send(Data(text.utf8))
                    }
                }
                Divider().frame(height: 22).overlay(Color.white.opacity(0.2))
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
        }
        .background(.ultraThinMaterial)
    }

    private func iconKey(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(.callout, weight: .medium))
                .frame(minWidth: 40)
                .padding(.vertical, 6)
                .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
        }
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
