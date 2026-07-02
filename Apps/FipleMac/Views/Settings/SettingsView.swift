import AppKit
import FipleKit
import ServiceManagement
import SwiftUI

/// Settings — mirrors the iOS remote's section order (Connection → Preferences →
/// About). No account by design (Fiple is local-only: no cloud, no backend).
struct SettingsView: View {
    let server: ServerController
    let remoteFiles: RemoteFilesController

    @Environment(\.openURL) private var openURL
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var newIgnoredSubfolder = ""

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

                // Off-LAN files (CloudKit) are disabled for the 1.0 release.
                if AppFeatures.remoteFiles {
                    section("Remote File Access") {
                        remoteFilesRow
                        Divider().padding(.leading, Theme.Spacing.md)
                        ignoredSubfoldersRow
                    }
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
                Toggle("Launch at Login", isOn: Binding(
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

    private var remoteFilesRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Keep recent files available on my phone")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle("Remote File Access", isOn: Binding(
                    get: { remoteFiles.isEnabled },
                    set: { remoteFiles.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.Palette.brand)
            }
            Text(remoteFiles.status)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Recent files from Desktop, Documents and Downloads are cached in your private iCloud so you can download them from the phone anywhere — even when this Mac is asleep. Originals are never modified; turning this off clears the cloud cache.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var ignoredSubfoldersRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Ignored Subfolders").font(.system(size: 14, weight: .medium))
            Text("Files inside these subfolders of Desktop, Documents and Downloads are never cached. Adding one removes its files from the cloud cache.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(remoteFiles.ignoredSubfolders, id: \.self) { name in
                HStack {
                    Text(name).font(.system(size: 13))
                    Spacer()
                    Button {
                        remoteFiles.removeIgnoredSubfolder(name)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop ignoring \(name)")
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Subfolder name, e.g. Private or Work/Secret", text: $newIgnoredSubfolder)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit(addIgnoredSubfolder)
                Button("Add", action: addIgnoredSubfolder)
                    .disabled(newIgnoredSubfolder.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func addIgnoredSubfolder() {
        remoteFiles.addIgnoredSubfolder(newIgnoredSubfolder)
        newIgnoredSubfolder = ""
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
