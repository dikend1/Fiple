import FipleKit
import SwiftUI

/// The Tools tab: the phone→Mac utilities that don't need to crowd Home —
/// Send to Mac and Smart Trash. Home keeps just the daily
/// essentials (connection, Terminal, workspaces, Fiple Bar).
struct ToolsView: View {
    let controller: RemoteController

    @State private var showSendSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    PageTitle("Tools")

                    toolRow(icon: "square.and.arrow.up", title: "Send to Mac",
                            subtitle: "Files to Downloads, text to clipboard",
                            enabled: controller.isConnected) { showSendSheet = true }
                        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 16))

                    if !controller.trashCandidates.isEmpty {
                        trashRow
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
        .sheet(isPresented: $showSendSheet) { SendToMacView(controller: controller) }
    }

    private var trashRow: some View {
        let candidates = controller.trashCandidates
        let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        return NavigationLink {
            TrashReviewView(controller: controller)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "trash.fill").font(.fiple(20, .semibold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Trash").font(.fiple(17, .semibold))
                    Text("Free up \(total)").font(.fiple(13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(candidates.count)")
                    .font(.fiple(13, .semibold))
                    .foregroundStyle(Theme.Palette.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.Palette.secondary.opacity(0.12), in: Capsule())
                Image(systemName: "chevron.right").font(.fiple(13, .semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.Palette.label)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func toolRow(
        icon: String, title: String, subtitle: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon).font(.fiple(20, .semibold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.fiple(17, .semibold))
                    Text(subtitle).font(.fiple(13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.fiple(13, .semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.Palette.label)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
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
