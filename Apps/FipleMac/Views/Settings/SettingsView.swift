import AppKit
import FipleKit
import ServiceManagement
import SwiftUI

/// Settings — mirrors the iOS remote's section order (Connection → Preferences →
/// About). No account by design (Fiple is local-only: no cloud, no backend).
struct SettingsView: View {
    let server: ServerController

    @Environment(\.openURL) private var openURL
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(title: "Settings", subtitle: "About Fiple and app controls.")

                section("Connection") {
                    settingRow(title: "Connection", value: connectionText)
                }

                section("Preferences") {
                    launchAtLoginRow
                }

                section("About") {
                    settingRow(title: "Version", value: version)
                    Divider().padding(.leading, Theme.Spacing.md)
                    linkRow(title: "Help & Support", url: FipleLinks.support)
                    Divider().padding(.leading, Theme.Spacing.md)
                    linkRow(title: "Privacy Policy", url: FipleLinks.privacy)
                    Divider().padding(.leading, Theme.Spacing.md)
                    linkRow(title: "Terms of Service", url: FipleLinks.terms)
                }

                HStack {
                    if server.status == .connected {
                        Button("Disconnect iPhone", role: .destructive) { Task { await server.disconnect() } }
                    }
                    Spacer()
                    Button("Quit Fiple") { NSApplication.shared.terminate(nil) }
                }
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private var connectionText: String {
        switch server.status {
        case .connected: "iPhone connected"
        case .advertising: "Waiting for iPhone"
        case .idle: "Off"
        }
    }

    // MARK: Rows

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Launch at Login").font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.Palette.brand)
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            // Keep the toggle in sync with the real service state on failure.
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "Couldn't update Launch at Login."
        }
    }

    private func settingRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func linkRow(title: String, url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack {
                Text(title).font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: Section container

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.Spacing.xs)
            VStack(spacing: 0) { content() }
                .padding(Theme.Spacing.sm)
                .fipleCard()
        }
    }
}
