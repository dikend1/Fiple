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
    @FocusState private var passwordFocused: Bool
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
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                    Text("Done").font(.system(size: 15, weight: .semibold))
                }
            }
            .tint(.white)
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(Theme.Palette.brand).frame(width: 7, height: 7)
                    .shadow(color: Theme.Palette.brand.opacity(0.7), radius: 3)
                Text("Terminal")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            // Balances the leading button so the title stays centred.
            HStack(spacing: 4) {
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                Text("Done").font(.system(size: 15, weight: .semibold))
            }.opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(white: 0.06))
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5), alignment: .bottom)
    }

    @ViewBuilder
    private func failureView(_ session: TerminalSession, message: String) -> some View {
        if session.lastAuthFailReason == .badPassword {
            passwordUnlockView
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

    /// Unlock the terminal by entering the Mac's master password. Styled to match
    /// the dark terminal: a green key badge, a monospace field with the reveal
    /// toggle inline, and a full-width brand-green Connect.
    private var passwordUnlockView: some View {
        VStack(spacing: 28) {
            VStack(spacing: 18) {
                Image("FipleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                VStack(spacing: 8) {
                    Text("Unlock terminal")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Enter the master password you set on your Mac.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            passwordField

            VStack(spacing: 12) {
                Button(action: submitRetry) {
                    Text("Connect")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(canConnect ? Theme.Palette.brand : Color.white.opacity(0.12))
                        )
                        .foregroundStyle(canConnect ? .white : .white.opacity(0.4))
                }
                .disabled(!canConnect)

                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
    }

    private var canConnect: Bool { retryPassword.count >= 4 }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.35))
            ZStack(alignment: .leading) {
                if retryPassword.isEmpty {
                    Text("Master password").foregroundStyle(.white.opacity(0.3))
                }
                Group {
                    if showRetryPassword {
                        TextField("", text: $retryPassword)
                    } else {
                        SecureField("", text: $retryPassword)
                    }
                }
                .foregroundStyle(.white)
                .tint(Theme.Palette.brand)
                .font(.system(size: 16, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($passwordFocused)
                .onSubmit(submitRetry)
            }
            Button {
                showRetryPassword.toggle()
            } label: {
                Image(systemName: showRetryPassword ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(passwordFocused ? Theme.Palette.brand : Color.white.opacity(0.12),
                                lineWidth: passwordFocused ? 1.5 : 1)
                )
        )
        .animation(.easeOut(duration: 0.15), value: passwordFocused)
        .onAppear { passwordFocused = true }
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
            HStack(spacing: 7) {
                iconKey("doc.on.clipboard", accent: true) {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        session.send(Data(text.utf8))
                    }
                }
                key("esc") { session.send(Data([0x1b])) }
                key("tab") { session.send(Data([0x09])) }
                key("⌃C") { session.send(Data([0x03])) }
                sep
                key("~") { session.send(Data("~".utf8)) }
                key("/") { session.send(Data("/".utf8)) }
                key("|") { session.send(Data("|".utf8)) }
                key("-") { session.send(Data("-".utf8)) }
                sep
                key("↑") { session.send(Data([0x1b, 0x5b, 0x41])) }
                key("↓") { session.send(Data([0x1b, 0x5b, 0x42])) }
                key("←") { session.send(Data([0x1b, 0x5b, 0x44])) }
                key("→") { session.send(Data([0x1b, 0x5b, 0x43])) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(Color(white: 0.10))
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5), alignment: .top)
    }

    private var sep: some View {
        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 22).padding(.horizontal, 2)
    }

    private func iconKey(_ systemName: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 15, weight: .medium))
                .frame(minWidth: 42, minHeight: 32)
                .background(accent ? Theme.Palette.brand.opacity(0.9) : Color(white: 0.22),
                           in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
        }
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(minWidth: 42, minHeight: 32)
                .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
        }
    }
}
