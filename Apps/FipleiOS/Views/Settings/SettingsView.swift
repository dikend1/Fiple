import SwiftUI

/// Settings: connected devices, app preferences, and the about/legal section.
/// All controls are presentation-only stand-ins for now.
struct SettingsView: View {
    let controller: RemoteController

    @State private var launchAtLogin = true
    @State private var confirmingUnpair = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    devices
                    preferences
                    about
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Settings")
            .alert("Disconnect this Mac?", isPresented: $confirmingUnpair) {
                Button("Disconnect", role: .destructive) { Task { await controller.disconnect() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter the pairing code again to reconnect.")
            }
        }
    }

    // MARK: Connected devices

    private var devices: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GroupLabel("Connected Devices")

            Button { confirmingUnpair = true } label: {
                HStack(spacing: Theme.Spacing.md) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "#0E1116"))
                        .overlay(
                            LinearGradient(
                                colors: [Theme.Palette.brand.opacity(0.5), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ).clipShape(RoundedRectangle(cornerRadius: 10)).padding(2)
                        )
                        .frame(width: 54, height: 38)
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
            }
            .buttonStyle(.plain)
            .fipleCard()

            Button { Task { await controller.disconnect() } } label: {
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
                SettingsRow(icon: "circle.dashed", title: "Appearance", value: "System")
                rowDivider
                SettingsToggleRow(icon: "bolt.fill", title: "Launch at Login", isOn: $launchAtLogin)
                rowDivider
                SettingsRow(icon: "bell", title: "Notifications")
                rowDivider
                SettingsRow(icon: "circle.circle", title: "Default Browser", value: "Chrome")
                rowDivider
                SettingsRow(icon: "globe", title: "Language", value: "English")
            }
            .fipleCard()
        }
    }

    // MARK: About

    private var about: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GroupLabel("About")

            VStack(spacing: 0) {
                SettingsRow(icon: "info.circle", title: "About Fiple")
                rowDivider
                SettingsRow(icon: "questionmark.circle", title: "Help & Support")
                rowDivider
                SettingsRow(icon: "lock", title: "Privacy Policy")
                rowDivider
                SettingsRow(icon: "doc.text", title: "Terms of Service")
            }
            .fipleCard()
        }
    }

    private var rowDivider: some View { Divider().padding(.leading, 56) }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
    }
}

/// Uppercase grouped-list section label.
private struct GroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Theme.Palette.label)
            .padding(.leading, 4)
    }
}

/// A standard tappable settings row with an optional trailing value.
private struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil

    var body: some View {
        Button {} label: {
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
        }
        .buttonStyle(.plain)
    }
}

/// A settings row with a trailing toggle.
private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

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
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.Palette.brand)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm + 2)
    }
}

#Preview {
    SettingsView(controller: RemoteController())
}
