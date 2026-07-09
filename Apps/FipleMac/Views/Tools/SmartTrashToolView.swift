import FipleKit
import SwiftUI

/// The Smart Trash feature page: enable the stale-file scan, choose the
/// staleness threshold, and manage the granted folders. A first-class page
/// (not a Settings section), mirroring the iOS Tools tab.
struct SmartTrashToolView: View {
    let server: ServerController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(
                    title: "Smart Trash",
                    subtitle: "Find files you stopped using and review them from your iPhone."
                )

                card
                note
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
            .pageColumn(maxWidth: 800)
        }
    }

    private var card: some View {
        let trash = server.trash
        return VStack(alignment: .leading, spacing: 0) {
            headerRow(trash)

            if trash.enabled {
                Divider().padding(.leading, 52)
                thresholdRow(trash)
                Divider().padding(.leading, 52)
                folderRows(trash)
            }
        }
        .padding(Theme.Spacing.sm)
        .fipleCard()
    }

    private func headerRow(_ trash: TrashController) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Palette.brand.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand))
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Trash").font(.system(size: 14, weight: .medium))
                Text(trash.candidates.isEmpty
                     ? "Scan chosen folders for files you haven't opened in a while."
                     : "\(trash.candidates.count) file(s) waiting for review on your iPhone.")
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

    private func thresholdRow(_ trash: TrashController) -> some View {
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
    private func folderRows(_ trash: TrashController) -> some View {
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

    private var note: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Files stay in place until you review them. Anything removed goes to the macOS Trash, never deleted permanently.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}
