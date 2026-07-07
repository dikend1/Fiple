import SwiftUI
import UIKit
import Combine
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
    /// A password the user typed on the inline retry field, to remember once it
    /// authenticates (may differ from the one passed in).
    @State private var retryPassword = ""
    @State private var showRetryPassword = false
    @State private var pendingRememberPassword: String?
    /// Keyboard height + bottom safe area, so we can lift the terminal so the
    /// line you're typing is never hidden behind the keyboard.
    @State private var keyboardHeight: CGFloat = 0
    @State private var bottomSafeArea: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    /// How much to lift the terminal so its bottom clears the keyboard (the
    /// keyboard frame already includes the home-indicator area we'd otherwise
    /// double-count).
    private var keyboardInset: CGFloat { max(0, keyboardHeight - bottomSafeArea) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                content(for: session)
            } else {
                ProgressView().tint(.white)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear { bottomSafeArea = proxy.safeAreaInsets.bottom }
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = frame.height }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = 0 }
        }
        .task {
            guard session == nil else { return }
            let session = TerminalSession(
                host: host, port: port, token: pairingToken, password: masterPassword,
                // A Face-ID password (not a fresh typed one) was valid before, so
                // allow quiet retries if the Mac rejects it right after a restart.
                passwordPrevalidated: !rememberOnSuccess
            )
            self.session = session
            await session.connect()
        }
        .onChange(of: scenePhase) { _, phase in
            session?.scenePhaseChanged(active: phase == .active)
        }
        .onChange(of: session?.phase) { _, phase in
            guard let phase else { return }
            if phase == .ready, !didRemember {
                // Remember whichever password just authenticated: a corrected one
                // typed on the inline field wins, else the initial typed one.
                if let corrected = pendingRememberPassword {
                    didRemember = true
                    TerminalCredentialStore.save(corrected)
                } else if rememberOnSuccess {
                    didRemember = true
                    TerminalCredentialStore.save(masterPassword)
                }
            }
            if case .failed = phase, session?.lastAuthFailReason == .badPassword {
                // A wrong (likely stale) saved password — forget it so it isn't
                // reused; the inline field below lets the user correct it.
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
            // Lift the whole terminal above the keyboard so the line you're
            // typing stays visible; we drive this ourselves instead of SwiftUI's
            // auto-avoidance (which SwiftTerm's UIScrollView doesn't cooperate with).
            .padding(.bottom, keyboardInset)
            .ignoresSafeArea(.keyboard, edges: .bottom)
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

    @ViewBuilder
    private func failureView(_ session: TerminalSession, message: String) -> some View {
        if session.lastAuthFailReason == .badPassword {
            // Correct the password in place — no bounce back to Home.
            VStack(spacing: 20) {
                Image(systemName: "key.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text("Enter master password").font(.headline)
                    Text("Type the password you set on your Mac.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack {
                    ZStack {
                        SecureField("Master password", text: $retryPassword)
                            .opacity(showRetryPassword ? 0 : 1)
                            .disabled(showRetryPassword)
                        TextField("Master password", text: $retryPassword)
                            .opacity(showRetryPassword ? 1 : 0)
                            .disabled(!showRetryPassword)
                    }
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(submitRetry)
                    Button {
                        showRetryPassword.toggle()
                    } label: {
                        Image(systemName: showRetryPassword ? "eye.slash" : "eye")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: 280)
                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered).tint(.white)
                    Button("Connect", action: submitRetry)
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        .disabled(retryPassword.count < 4)
                }
            }
            .foregroundStyle(.white).padding()
        } else {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44)).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text("Couldn’t open terminal").font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
            }
            .foregroundStyle(.white).padding()
        }
    }

    private func submitRetry() {
        guard retryPassword.count >= 4 else { return }
        pendingRememberPassword = retryPassword // remember it if it works
        session?.retry(withPassword: retryPassword)
        retryPassword = ""
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
