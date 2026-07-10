import FipleKit
import SwiftUI

/// The Tools tab: the phone→Mac utilities that don't need to crowd Home —
/// Send to Mac and Smart Trash — as a two-up grid of feature cards. Each card
/// carries a live fact (candidate count, reclaimable size), so the page reads
/// as a small dashboard rather than two thin rows adrift on an empty screen.
struct ToolsView: View {
    let controller: RemoteController

    @State private var showSendSheet = false

    // Terminal unlock flow (moved here from Home with the entry itself).
    @State private var showTerminalSheet = false
    @State private var terminalPassword = ""
    @State private var openTerminal = false
    /// Whether the current password came from Face ID (already saved) vs typed
    /// (save it only once it actually authenticates).
    @State private var terminalFromBiometrics = false
    @FocusState private var passwordFocused: Bool

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 2
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    PageTitle("Tools")

                    // Terminal is the flagship — a full-width hero row. The two
                    // beam/cleanup tools pair up beneath it, so three tools
                    // never leave an orphan hole in a 2-up grid.
                    Button {
                        Task { await beginTerminal() }
                    } label: {
                        TerminalHeroCard()
                    }
                    .buttonStyle(ToolCardPressStyle())
                    .disabled(controller.terminalTarget == nil)
                    .opacity(controller.terminalTarget == nil ? 0.45 : 1)

                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        Button {
                            showSendSheet = true
                        } label: {
                            ToolCard(
                                icon: "square.and.arrow.up",
                                tint: Theme.Palette.brand,
                                title: "Send to Mac",
                                detail: "Photos & files",
                                caption: "Land in Downloads"
                            )
                        }
                        .buttonStyle(ToolCardPressStyle())
                        .disabled(!controller.isConnected)
                        .opacity(controller.isConnected ? 1 : 0.45)

                        NavigationLink {
                            TrashReviewView(controller: controller)
                        } label: {
                            ToolCard(
                                icon: "trash",
                                tint: .orange,
                                title: "Smart Trash",
                                detail: trashDetail,
                                caption: trashCaption,
                                badge: controller.trashCandidates.isEmpty
                                    ? nil : "\(controller.trashCandidates.count)"
                            )
                        }
                        .buttonStyle(ToolCardPressStyle())
                        .disabled(controller.trashCandidates.isEmpty)
                        .opacity(controller.trashCandidates.isEmpty ? 0.45 : 1)
                    }

                    if !controller.isConnected {
                        Text("Connect to your Mac on the same Wi-Fi to use tools.")
                            .font(.fiple(13))
                            .foregroundStyle(Theme.Palette.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.tabBarClearance)
            }
            .background(Theme.Palette.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showSendSheet) {
            SendToMacView(controller: controller)
                // Two picker rows don't need a full screen — a compact card
                // keeps the context (and the app) visible behind.
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTerminalSheet) { terminalPasswordSheet }
        .fullScreenCover(isPresented: $openTerminal) {
            if let target = controller.terminalTarget {
                TerminalScreen(
                    host: target.host, port: target.port,
                    pairingToken: target.token, masterPassword: terminalPassword,
                    rememberOnSuccess: !terminalFromBiometrics
                )
            }
        }
    }

    // MARK: Terminal unlock

    /// Opens the terminal: unlock with Face ID if a password is already
    /// remembered, otherwise ask for it (typed passwords are saved only after
    /// they successfully authenticate — see TerminalScreen).
    private func beginTerminal() async {
        if TerminalCredentialStore.hasStoredPassword() {
            if let password = await TerminalCredentialStore.retrieve(reason: "Unlock the Mac terminal") {
                terminalPassword = password
                terminalFromBiometrics = true
                openTerminal = true
                return
            }
            // Biometry cancelled or failed — fall back to typing.
        }
        terminalPassword = ""
        terminalFromBiometrics = false
        showTerminalSheet = true
    }

    private var terminalPasswordSheet: some View {
        NavigationStack {
            Form {
                Section("Master Password") {
                    SecureField("Enter master password", text: $terminalPassword)
                        .textContentType(.password)
                        .focused($passwordFocused)
                }
            }
            .navigationTitle("Open Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTerminalSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        // Don't save yet — only after it authenticates (so a
                        // wrong password never gets remembered for Face ID).
                        showTerminalSheet = false
                        openTerminal = true
                    }
                    .disabled(terminalPassword.count < 4)
                }
            }
            .onAppear { passwordFocused = true }
        }
        .presentationDetents([.height(200)])
    }

    /// The live fact each card leads with.
    private var trashDetail: String {
        let candidates = controller.trashCandidates
        guard !candidates.isEmpty else { return "All clean" }
        let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return "Free up \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }

    private var trashCaption: String {
        let count = controller.trashCandidates.count
        guard count > 0 else { return "No stale files found" }
        return count == 1 ? "1 file to review" : "\(count) files to review"
    }
}

/// One square-ish feature card: tinted icon up top, the tool's name, then the
/// live fact it currently offers — with an optional count badge.
private struct ToolCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let caption: String
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.fiple(19, .semibold))
                            .foregroundStyle(tint)
                    )
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.fiple(13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint, in: Capsule())
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(title)
                .font(.fiple(16, .semibold))
                .foregroundStyle(Theme.Palette.label)
            Text(detail)
                .font(.fiple(14, .medium))
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(caption)
                .font(.fiple(12))
                .foregroundStyle(Theme.Palette.secondary)
                .padding(.top, 1)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 148)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.Palette.hairline)
        )
    }
}

/// The Terminal hero: a full-width row led by a miniature "terminal window"
/// mark (black squircle, mono `>_`) — the one place the app's dark terminal
/// identity shows on this page.
private struct TerminalHeroCard: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(">_")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Palette.brand)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Terminal")
                    .font(.fiple(17, .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text("Run a shell on your Mac")
                    .font(.fiple(13))
                    .foregroundStyle(Theme.Palette.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.fiple(13, .semibold))
                .foregroundStyle(Theme.Palette.secondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.Palette.hairline)
        )
    }
}

/// A gentle press-down so the cards feel tappable.
private struct ToolCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The screen's large title, matching Home's custom header style.
private struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.fiple(34, .bold))
            .foregroundStyle(Theme.Palette.label)
    }
}
