import AppKit
import SwiftUI

/// Minimal settings — app info and lifecycle. No account by design (Fiple is
/// local-only: no cloud, no backend).
struct SettingsView: View {
    let server: ServerController

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(title: "Settings", subtitle: "About Fiple and app controls.")

                VStack(spacing: 0) {
                    settingRow(title: "Connection", value: connectionText)
                    Divider().padding(.leading, Theme.Spacing.md)
                    settingRow(title: "Version", value: version)
                }
                .padding(Theme.Spacing.sm)
                .fipleCard()

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
    }

    private var connectionText: String {
        switch server.status {
        case .connected: "iPhone connected"
        case .advertising: "Waiting for iPhone"
        case .idle: "Off"
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
}
