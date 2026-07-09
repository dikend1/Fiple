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
    @State private var masterPassword = ""
    @State private var showingPasswordField = false

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
                    connectionRow
                }

                section("Preferences") {
                    launchAtLoginRow
                }

                section("Terminal") {
                    terminalSection
                }

                section("Smart Trash") {
                    trashSection
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
            .pageColumn(maxWidth: 800)
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

    private var connectionColor: Color {
        switch server.status {
        case .connected: Theme.Palette.connected
        case .advertising: .orange
        case .idle: .secondary.opacity(0.5)
        }
    }

    // MARK: Rows

    /// Same anatomy as the feature sections (icon tile + title + trailing
    /// state), so the page reads as one system instead of two row styles.
    private var connectionRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            settingIcon("iphone.gen3")
            Text("iPhone").font(.system(size: 14, weight: .medium))
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(connectionColor).frame(width: 8, height: 8)
                Text(connectionText).font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.md)
    }

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.md) {
                settingIcon("power")
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
                    .padding(.leading, 40)
            }
        }
        .padding(Theme.Spacing.md)
    }

    /// The small tinted icon square every feature header uses.
    private func settingIcon(_ systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.Palette.brand.opacity(0.15))
            .frame(width: 28, height: 28)
            .overlay(Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.brand))
    }

    // MARK: Terminal

    @ViewBuilder
    private var terminalSection: some View {
        let terminal = server.terminal
        VStack(alignment: .leading, spacing: 0) {
            terminalHeaderRow(terminal)

            Divider().padding(.leading, 52)
            terminalPasswordRow(terminal)

            if terminal.enabled {
                Divider().padding(.leading, 52)
                terminalStatusRow(terminal)
                terminalSecurityNote
            }
        }
    }

    /// Icon + title + subtitle + the enable toggle.
    private func terminalHeaderRow(_ terminal: TerminalController) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Palette.brand.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "terminal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand))
            VStack(alignment: .leading, spacing: 2) {
                Text("Terminal Access").font(.system(size: 14, weight: .medium))
                Text(terminal.hasPassword
                     ? "Run a shell on this Mac from your iPhone."
                     : "Set a master password below to turn this on.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Terminal Access", isOn: Binding(
                get: { terminal.enabled },
                set: { terminal.setEnabled($0) }
            ))
            .labelsHidden().toggleStyle(.switch).tint(Theme.Palette.brand)
            .disabled(!terminal.hasPassword)
            .help(terminal.hasPassword ? "" : "Set a master password first")
        }
        .padding(Theme.Spacing.md)
    }

    /// Compact when a password is set (a Change… button reveals the field);
    /// prominent field when none is set yet (the required first step).
    @ViewBuilder
    private func terminalPasswordRow(_ terminal: TerminalController) -> some View {
        if terminal.hasPassword && !showingPasswordField {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "key.fill").font(.system(size: 12))
                    .foregroundStyle(.secondary).frame(width: 28)
                Text("Master Password").font(.system(size: 14, weight: .medium))
                Text("Set").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.brand)
                Spacer()
                Button("Change…") { showingPasswordField = true }
                    .controlSize(.small)
            }
            .padding(Theme.Spacing.md)
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "key.fill").font(.system(size: 12))
                    .foregroundStyle(.secondary).frame(width: 28)
                SecureField(terminal.hasPassword ? "New password (min 4 characters)"
                                                 : "Create a password (min 4 characters)",
                            text: $masterPassword)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Button(terminal.hasPassword ? "Save" : "Set") {
                    terminal.setPassword(masterPassword)
                    masterPassword = ""
                    showingPasswordField = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(masterPassword.count < 4)
                if terminal.hasPassword {
                    Button("Cancel") { masterPassword = ""; showingPasswordField = false }
                        .controlSize(.regular)
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
        }
    }

    /// A humane status: a coloured dot + plain-language state instead of a port.
    private func terminalStatusRow(_ terminal: TerminalController) -> some View {
        let connected = terminal.activeSessions > 0
        return HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(connected ? Theme.Palette.connected : Color.orange)
                .frame(width: 8, height: 8).frame(width: 28)
            Text(connected
                 ? (terminal.activeSessions == 1 ? "iPhone connected"
                                                 : "\(terminal.activeSessions) iPhones connected")
                 : "Ready — waiting for iPhone")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            // The port stays available for troubleshooting, but only on hover.
            if terminal.port != 0 {
                Text("Port \(terminal.port)").font(.system(size: 11))
                    .foregroundStyle(.tertiary).help("The terminal service is listening on this port")
            }
        }
        .padding(Theme.Spacing.md)
    }

    /// Honest note about the power this grants (HIG: disclose strong capabilities).
    private var terminalSecurityNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "lock.shield").font(.system(size: 12))
                .foregroundStyle(.secondary).frame(width: 28)
            Text("Anyone with the master password and your paired iPhone can run any command on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: Smart Trash

    @ViewBuilder
    private var trashSection: some View {
        let trash = server.trash
        VStack(alignment: .leading, spacing: 0) {
            trashHeaderRow(trash)

            if trash.enabled {
                Divider().padding(.leading, 52)
                trashThresholdRow(trash)
                Divider().padding(.leading, 52)
                trashFoldersRows(trash)
                trashNote
            }
        }
    }

    private func trashHeaderRow(_ trash: TrashController) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Palette.brand.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand))
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Trash").font(.system(size: 14, weight: .medium))
                Text("Find stale files and review them from your iPhone.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Smart Trash", isOn: Binding(
                get: { trash.enabled },
                set: { trash.setEnabled($0) }
            ))
            .labelsHidden().toggleStyle(.switch).tint(Theme.Palette.brand)
        }
        .padding(Theme.Spacing.md)
    }

    private func trashThresholdRow(_ trash: TrashController) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "calendar").font(.system(size: 12))
                .foregroundStyle(.secondary).frame(width: 28)
            Text("Consider files stale after").font(.system(size: 14, weight: .medium))
            Spacer()
            Picker("Staleness threshold", selection: Binding(
                get: { trash.thresholdDays },
                set: { trash.setThresholdDays($0) }
            )) {
                Text("15 days").tag(15)
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
            }
            .labelsHidden()
            .frame(width: 110)
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private func trashFoldersRows(_ trash: TrashController) -> some View {
        ForEach(trash.folders, id: \.self) { folder in
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder.fill").font(.system(size: 12))
                    .foregroundStyle(.secondary).frame(width: 28)
                Text(folder.lastPathComponent).font(.system(size: 14, weight: .medium))
                Text(folder.path).font(.system(size: 11)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Remove") { trash.removeFolder(folder) }
                    .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            Divider().padding(.leading, 52)
        }
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "plus.circle").font(.system(size: 12))
                .foregroundStyle(.secondary).frame(width: 28)
            Button(trash.folders.isEmpty ? "Choose Folders to Scan…" : "Add Folder…") {
                trash.grantFolder()
            }
            .controlSize(.regular)
            Spacer()
            if trash.folders.isEmpty {
                Text("No folders granted yet").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.md)
    }

    private var trashNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 12))
                .foregroundStyle(.secondary).frame(width: 28)
            Text("Files stay in place until you review them. Anything removed goes to the macOS Trash, never deleted permanently.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
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
