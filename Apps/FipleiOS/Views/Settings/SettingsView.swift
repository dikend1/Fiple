import FipleKit
import SwiftUI

/// Settings: connected devices, app preferences, and the about/legal section.
/// Mirrors the Mac app's section order (Devices → Preferences → About); every
/// control performs a real action.
struct SettingsView: View {
    let controller: RemoteController

    @Environment(\.openURL) private var openURL
    @State private var confirmingUnpair = false
    @State private var confirmingClearHistory = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    devices
                    preferences
                    about
                    #if DEBUG
                    debugTools
                    #endif
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.tabBarClearance)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Settings")
            .alert("Disconnect this Mac?", isPresented: $confirmingUnpair) {
                Button("Disconnect", role: .destructive) { Task { await controller.disconnect() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter the pairing code again to reconnect.")
            }
            .alert("Clear launch history?", isPresented: $confirmingClearHistory) {
                Button("Clear", role: .destructive) { controller.clearRecents() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the list of recently launched items on this iPhone.")
            }
        }
    }

    // MARK: Connected devices

    private var devices: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GroupLabel("Connected Devices")

            Button { confirmingUnpair = true } label: {
                HStack(spacing: Theme.Spacing.md) {
                    // The paired Mac's device glyph on a soft brand tile — same
                    // hardware family the connection card shows.
                    Image(systemName: deviceSymbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.Palette.brand)
                        .frame(width: 54, height: 40)
                        .background(
                            Theme.Palette.brand.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(controller.macName ?? "Your Mac")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.label)
                        Text(controller.phase == .connected ? "Connected" : "Offline")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(controller.phase == .connected ? Theme.Palette.connected : Theme.Palette.secondary)
                    }
                    Spacer()
                    chevron
                }
                .padding(Theme.Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fipleCard()

            Button {
                Task {
                    await controller.disconnect()
                    // Actually open the pairing flow — clearing the token alone
                    // leaves the user staring at the same screen when no Mac is
                    // discoverable yet.
                    controller.requestPairing()
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.Palette.brand)
                    Text("Pair New Mac")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.label)
                    Spacer()
                    chevron
                }
                .padding(Theme.Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fipleCard()
        }
    }

    // MARK: Preferences

    private var preferences: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GroupLabel("Preferences")

            VStack(spacing: 0) {
                SettingsRow(
                    icon: controller.entitlements.isPro ? "checkmark.seal.fill" : "crown.fill",
                    title: controller.entitlements.isPro ? "Fiple Pro — Active" : "Get Fiple Pro",
                    value: controller.entitlements.isPro ? nil : "Unlock all"
                ) {
                    if !controller.entitlements.isPro { controller.paywallRequested = true }
                }
                rowDivider
                SettingsRow(icon: "clock.arrow.circlepath", title: "Clear Launch History") {
                    confirmingClearHistory = true
                }
            }
            .fipleCard()
        }
    }

    // MARK: About

    private var about: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GroupLabel("About")

            VStack(spacing: 0) {
                SettingsValueRow(icon: "info.circle", title: "Version", value: version)
                rowDivider
                SettingsRow(icon: "questionmark.circle", title: "Help & Support") {
                    openURL(FipleLinks.support)
                }
                rowDivider
                SettingsRow(icon: "lock", title: "Privacy Policy") {
                    openURL(FipleLinks.privacy)
                }
                rowDivider
                SettingsRow(icon: "doc.text", title: "Terms of Service") {
                    openURL(FipleLinks.terms)
                }
            }
            .fipleCard()
        }
    }

    #if DEBUG
    /// Debug-only paywall testing aids: flip back to the free tier, and shrink the
    /// free workspace limit so locked cards appear without 9+ real workspaces.
    private var debugTools: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GroupLabel("Debug")

            VStack(spacing: 0) {
                SettingsRow(icon: "sparkles", title: "Replay onboarding") {
                    // Clear the seen-flag and ask RootView to present welcome
                    // again (it shows once this Settings tab is left).
                    UserDefaults.standard.removeObject(forKey: "fiple.hasSeenWelcome")
                    controller.replayWelcomeRequested = true
                }
                rowDivider
                SettingsRow(icon: "hand.draw", title: "Replay Smart Trash guide") {
                    // Clear the seen-flag; the guide shows on the next visit
                    // to the Smart Trash deck (needs candidates to review).
                    UserDefaults.standard.removeObject(forKey: "com.fiple.trash.gestureGuideSeen")
                }
                rowDivider
                SettingsRow(icon: "arrow.counterclockwise", title: "Reset Pro (back to free)") {
                    controller.entitlements.debugReset()
                }
                rowDivider
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "lock.badge.clock")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Palette.label)
                        .frame(width: 26)
                    Text("Free limit (apps & workspaces)")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.label)
                    Spacer()
                    Stepper(
                        "\(controller.debugFreeLimitOverride ?? FreeTierGate.defaultFreeLimit)",
                        value: Binding(
                            get: { controller.debugFreeLimitOverride ?? FreeTierGate.defaultFreeLimit },
                            set: { controller.debugFreeLimitOverride = $0 }
                        ),
                        in: 0...20
                    )
                    .labelsHidden()
                    Text("\(controller.debugFreeLimitOverride ?? FreeTierGate.defaultFreeLimit)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(minWidth: 24)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .fipleCard()
        }
    }
    #endif

    private var rowDivider: some View { Divider().padding(.leading, 56) }

    /// SF Symbol for the paired Mac's hardware family.
    private var deviceSymbol: String {
        switch controller.macKind {
        case .laptop: "laptopcomputer"
        case .iMac, .desktop: "desktopcomputer"
        case .macMini: "macmini"
        case .macStudio: "macstudio"
        case .macPro: "macpro.gen3"
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
    }
}

/// Grouped-list section label — quiet and secondary so it frames the cards
/// instead of competing with the big "Settings" title.
private struct GroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.Palette.secondary)
            .padding(.leading, 4)
    }
}

/// A standard tappable settings row with an optional trailing value.
private struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.Palette.label)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.label)
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md + 2)
            // Make the entire row tappable, not just the icon/label — the Spacer
            // and padding are dead zones without an explicit hit shape.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A non-interactive settings row showing a read-only value (e.g. app version).
private struct SettingsValueRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Palette.label)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Palette.label)
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.secondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md + 2)
    }
}

#Preview {
    SettingsView(controller: RemoteController())
}
