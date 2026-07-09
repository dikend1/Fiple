import FipleKit
import SwiftUI

/// The Terminal feature page: enable the phone shell, manage the master
/// password, and see the live listener state. A first-class page (not a
/// Settings section) — it mirrors the iOS Tools tab and leaves room to grow
/// (active-session list, per-session terminate).
struct TerminalToolView: View {
    let server: ServerController

    @State private var masterPassword = ""
    @State private var showingPasswordField = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(
                    title: "Terminal",
                    subtitle: "Run a shell on this Mac from your iPhone."
                )

                card
                securityNote
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
            .pageColumn(maxWidth: 800)
        }
    }

    private var card: some View {
        let terminal = server.terminal
        return VStack(alignment: .leading, spacing: 0) {
            headerRow(terminal)

            Divider().padding(.leading, 52)
            passwordRow(terminal)

            if terminal.enabled {
                Divider().padding(.leading, 52)
                statusRow(terminal)
            }
        }
        .padding(Theme.Spacing.sm)
        .fipleCard()
    }

    /// Icon + title + subtitle + the enable toggle.
    private func headerRow(_ terminal: TerminalController) -> some View {
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
                     ? "Open the Terminal from the Fiple app on your iPhone."
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
    private func passwordRow(_ terminal: TerminalController) -> some View {
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
    private func statusRow(_ terminal: TerminalController) -> some View {
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
    private var securityNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "lock.shield").font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Anyone with the master password and your paired iPhone can run any command on this Mac.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}
