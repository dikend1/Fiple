import SwiftUI
import UIKit
import Combine
import FipleKit

/// One tab in the terminal: a named, independently connected shell on the Mac.
/// All open tabs stay connected in parallel — each keeps its own SwiftTerm
/// emulator mounted (hidden when inactive) so background output accumulates and
/// is there the moment you switch.
@MainActor
@Observable
final class TerminalTab: Identifiable {
    let id = UUID()
    let name: String
    let session: TerminalSession
    /// Restored from a previous screen visit — dropped silently if its Mac
    /// shell turns out to have expired, instead of showing an error.
    let restored: Bool
    /// When the user last looked at this tab, for the unseen-output dot.
    var lastSeenAt = Date()

    init(name: String, session: TerminalSession, restored: Bool = false) {
        self.name = name
        self.session = session
        self.restored = restored
    }

    /// Output arrived after the user last had this tab on screen.
    var hasUnseenOutput: Bool {
        guard let output = session.lastOutputAt else { return false }
        return output > lastSeenAt
    }
}

/// Full-screen terminal on the phone. Owns up to ``maxTabs`` independent
/// ``TerminalSession`` tabs (e.g. three Claude Code chats side by side); a menu
/// in the top bar switches between them. Each session connects, authenticates,
/// and — crucially on iOS — resumes the same Mac shell when the app returns
/// from the background (the OS kills the socket within seconds).
struct TerminalScreen: View {
    let host: String
    let port: UInt16
    let pairingToken: String
    let masterPassword: String
    /// True when the password was typed (not from Face ID) — save it behind
    /// biometrics once it authenticates, so next time is one-tap Face ID.
    var rememberOnSuccess: Bool = false
    /// Fiple Pro state: one session is free forever (including Done-restore);
    /// parallel sessions are the Pro tier. Nil (previews/tests) = ungated.
    var entitlements: EntitlementStore?

    static let maxTabs = 5

    /// Whether another parallel session may open right now.
    private var canOpenAnotherSession: Bool {
        tabs.isEmpty || entitlements?.isPro != false
    }

    @State private var tabs: [TerminalTab] = []
    @State private var activeTabID: UUID?
    /// Session numbering keeps counting up ("Session 4" after closing 1–3), so a
    /// name never refers to two different shells within one screen's lifetime.
    @State private var nextSessionNumber = 1
    @State private var didRemember = false
    /// A password the user typed on the inline retry field, to remember once it
    /// authenticates (may differ from the one passed in).
    @State private var retryPassword = ""
    @State private var showRetryPassword = false
    @FocusState private var passwordFocused: Bool
    @State private var pendingRememberPassword: String?
    /// The Pro paywall, presented over the terminal when a second parallel
    /// session is requested without Pro.
    @State private var showPaywall = false
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

    private var activeTab: TerminalTab? {
        tabs.first { $0.id == activeTabID } ?? tabs.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let tab = activeTab {
                content(for: tab)
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
            guard tabs.isEmpty else { return }
            await restoreOrOpenTabs()
        }
        .onChange(of: scenePhase) { _, phase in
            for tab in tabs { tab.session.scenePhaseChanged(active: phase == .active) }
            // The saved list must survive a background jetsam, not just a
            // graceful screen close — snapshot it on the way out.
            if phase != .active { saveTabs() }
        }
        .onChange(of: activeTab?.session.phase) { _, phase in
            guard let phase, let session = activeTab?.session else { return }
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
            if case .failed = phase, session.lastAuthFailReason == .badPassword {
                // A wrong (likely stale) saved password — forget it so it isn't
                // reused; the inline field below lets the user correct it.
                TerminalCredentialStore.clear()
            }
        }
        // Closing the screen detaches every shell (they survive the grace period
        // on the Mac); it doesn't kill them — only closing a tab does that. The
        // remembered tab list lets the next visit reattach to whatever survived.
        .onDisappear {
            saveTabs()
            for tab in tabs { tab.session.close() }
        }
        .sheet(isPresented: $showPaywall) {
            if let entitlements {
                PaywallView(store: entitlements)
            }
        }
    }

    // MARK: Persistence — remember open shells across screen visits

    private struct SavedTab: Codable {
        let sessionID: String
        let name: String
    }
    private static let savedTabsKey = "fiple.terminal.savedTabs"

    private func saveTabs() {
        let saved = tabs.compactMap { tab in
            tab.session.sessionID.map { SavedTab(sessionID: $0, name: tab.name) }
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedTabsKey)
    }

    /// Reattach to the shells a previous visit left running (still within their
    /// grace period on the Mac). Dead ones are pruned as they report ended; if
    /// nothing survives, fall back to one fresh session — the user always lands
    /// in a working terminal.
    private func restoreOrOpenTabs() async {
        let saved = (UserDefaults.standard.data(forKey: Self.savedTabsKey))
            .flatMap { try? JSONDecoder().decode([SavedTab].self, from: $0) } ?? []

        guard !saved.isEmpty else {
            await openNewTab()
            return
        }
        // Free tier restores its one session; Pro restores everything. (A Pro
        // lapse between visits must not resurrect a whole locked tab set.)
        let restoreLimit = entitlements?.isPro == false ? 1 : Self.maxTabs
        for entry in saved.prefix(restoreLimit) {
            let session = TerminalSession(
                host: host, port: port, token: pairingToken, password: currentPassword,
                passwordPrevalidated: true, restoreSessionID: entry.sessionID
            )
            let tab = TerminalTab(name: entry.name, session: session, restored: true)
            tabs.append(tab)
            // Keep numbering ahead of restored names ("Session 3" → next is 4).
            if let number = Int(entry.name.replacingOccurrences(of: "Session ", with: "")) {
                nextSessionNumber = max(nextSessionNumber, number + 1)
            }
            Task { await session.connect() }
        }
        activeTabID = tabs.first?.id
        // Prune restored tabs whose shell expired; poll briskly so a dead
        // restore never delays landing in a working terminal. Restoration is
        // strictly best-effort: any restored tab that hasn't come up within the
        // deadline is abandoned too — the user must never sit on a spinner for
        // shells from last time. If nothing survives, open a fresh session.
        Task {
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(300))
                prune { $0.session.phase == .ended }
                if tabs.isEmpty {
                    await openNewTab()
                    return
                }
                // Every restored tab settled (ready or already pruned) — done.
                if tabs.allSatisfy({ !$0.restored || $0.session.phase == .ready }) { return }
            }
            // Deadline hit: give up on whatever is still limping.
            prune { $0.session.phase != .ready }
            if tabs.isEmpty { await openNewTab() }
        }
    }

    // MARK: Tabs

    /// The password that most recently authenticated — new tabs reuse it, so
    /// opening "Session 2" never re-asks what "Session 1" already proved.
    private var currentPassword: String {
        pendingRememberPassword ?? masterPassword
    }

    private func openNewTab() async {
        guard tabs.count < Self.maxTabs else { return }
        let session = TerminalSession(
            host: host, port: port, token: pairingToken, password: currentPassword,
            // The first tab's password may be fresh-typed; every later tab uses a
            // password that already authenticated a sibling, so quiet retries are
            // safe for it too.
            passwordPrevalidated: !rememberOnSuccess || !tabs.isEmpty
        )
        let tab = TerminalTab(name: "Session \(nextSessionNumber)", session: session)
        nextSessionNumber += 1
        tabs.append(tab)
        activate(tab)
        await session.connect()
    }

    /// Drops restored tabs matching `condition` and repairs the active id.
    private func prune(_ condition: (TerminalTab) -> Bool) {
        let doomed = tabs.filter { $0.restored && condition($0) }
        guard !doomed.isEmpty else { return }
        for tab in doomed {
            tab.session.close()
            tabs.removeAll { $0.id == tab.id }
        }
        if activeTab == nil { activeTabID = tabs.first?.id }
        saveTabs() // dead restores must not come back next visit
    }

    private func activate(_ tab: TerminalTab) {
        // Stamp the tab we're leaving so its dot only lights for output that
        // arrives after this moment.
        if let current = activeTab { current.lastSeenAt = Date() }
        activeTabID = tab.id
        tab.lastSeenAt = Date()
    }

    private func closeTab(_ tab: TerminalTab) {
        tab.session.endShell()
        tabs.removeAll { $0.id == tab.id }
        if activeTabID == tab.id { activeTabID = tabs.first?.id }
        // Drop it from the saved list too, so a jetsam right after this
        // doesn't restore a tab the user explicitly killed.
        saveTabs()
        if tabs.isEmpty { dismiss() }
    }

    @ViewBuilder
    private func content(for tab: TerminalTab) -> some View {
        let session = tab.session
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
                // EVERY ready tab keeps its emulator mounted — hidden tabs keep
                // consuming output, so switching shows what accumulated. A fresh
                // emulator per connection (`generation`) redraws the replayed
                // scrollback cleanly instead of appending it to stale content.
                ZStack {
                    ForEach(tabs.filter { $0.session.phase == .ready }) { readyTab in
                        SwiftTermView(session: readyTab.session)
                            .id("\(readyTab.id)-\(readyTab.session.generation)")
                            .opacity(readyTab.id == tab.id ? 1 : 0)
                            .allowsHitTesting(readyTab.id == tab.id)
                    }
                }
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

    /// A slim bar over the terminal. Leading: Done (detaches, never kills — the
    /// shells keep running on the Mac). Centre: the session menu — the current
    /// session's name opens the switcher, one row per tab with an activity dot
    /// (orange = unseen output, green = live, gray = reconnecting), plus New /
    /// Close Session.
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
            sessionMenu
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

    private var sessionMenu: some View {
        Menu {
            ForEach(tabs) { tab in
                Button {
                    activate(tab)
                } label: {
                    if tab.id == activeTab?.id {
                        Label(tab.name, systemImage: "checkmark")
                    } else if tab.hasUnseenOutput {
                        // The "which Claude finished?" signal: output arrived
                        // while this tab was in the background.
                        Label(tab.name, systemImage: "circle.fill")
                    } else {
                        Text(tab.name)
                    }
                }
            }
            Divider()
            Button {
                // Parallel sessions are the Pro tier: the first session is
                // free forever, the second opens the paywall instead.
                if canOpenAnotherSession {
                    Task { await openNewTab() }
                } else {
                    showPaywall = true
                }
            } label: {
                Label("New Session", systemImage: canOpenAnotherSession ? "plus" : "lock.fill")
            }
            .disabled(tabs.count >= Self.maxTabs)
            Button(role: .destructive) {
                if let tab = activeTab { closeTab(tab) }
            } label: {
                Label("Close Session", systemImage: "xmark")
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(anyUnseenOutput ? Color.orange : Theme.Palette.brand)
                    .frame(width: 7, height: 7)
                    .shadow(color: (anyUnseenOutput ? Color.orange : Theme.Palette.brand).opacity(0.7), radius: 3)
                Text(activeTab?.name ?? "Terminal")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                if tabs.count > 1 {
                    Text("\(tabs.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.85), in: Capsule())
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .accessibilityLabel("Sessions, \(activeTab?.name ?? "Terminal") active, \(tabs.count) open")
    }

    /// Any background tab produced output since it was last viewed.
    private var anyUnseenOutput: Bool {
        tabs.contains { $0.id != activeTab?.id && $0.hasUnseenOutput }
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
        activeTab?.session.retry(withPassword: retryPassword)
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
            // Order = usefulness on a phone: everything the soft keyboard
            // can't type (esc/tab/^C and the arrows — history, TUI menus)
            // sits before the fold; ~ / | - exist on the keyboard's symbols
            // plane, so they can afford to scroll.
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
                key("↑") { session.send(Data([0x1b, 0x5b, 0x41])) }
                key("↓") { session.send(Data([0x1b, 0x5b, 0x42])) }
                key("←") { session.send(Data([0x1b, 0x5b, 0x44])) }
                key("→") { session.send(Data([0x1b, 0x5b, 0x43])) }
                sep
                key("~") { session.send(Data("~".utf8)) }
                key("/") { session.send(Data("/".utf8)) }
                key("|") { session.send(Data("|".utf8)) }
                key("-") { session.send(Data("-".utf8)) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(Color(white: 0.10))
        // A soft fade on the trailing edge says "there's more" — without it
        // the cut-off keys past the fold are invisible.
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [Color(white: 0.10).opacity(0), Color(white: 0.10)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
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
