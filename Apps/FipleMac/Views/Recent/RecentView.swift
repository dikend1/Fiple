import FipleKit
import SwiftUI

/// Full launch history page. Each row re-runs its workspace on the Mac.
struct RecentView: View {
    let recents: RecentStore
    /// Re-run a record: re-dispatch a single action, or look up a workspace tile.
    var onRun: ((RunRecord) -> Void)?
    @State private var confirmingClear = false
    @State private var pendingRemoval: RunRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(title: "Recent", subtitle: "Tap to relaunch a workspace you opened recently.") {
                    if !recents.records.isEmpty {
                        Button("Clear", role: .destructive) { confirmingClear = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    RecentList(
                        records: recents.records,
                        emptyHint: "Launch a workspace from your iPhone to see it here.",
                        onRun: onRun,
                        onDelete: { pendingRemoval = $0 }
                    )
                }
                .padding(Theme.Spacing.lg)
                .fipleCard()
            }
            .padding(Theme.Spacing.xxl)
            .pageColumn(maxWidth: 900)
            .padding(.top, Theme.Spacing.sm)
        }
        .alert("Clear launch history?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { recents.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all \(recents.records.count) recent launches.")
        }
        .alert(
            "Remove this entry?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { record in
            Button("Remove", role: .destructive) { recents.delete(record.id) }
            Button("Cancel", role: .cancel) {}
        } message: { record in
            Text("Removes the “\(record.tileName)” launch from your history.")
        }
    }
}

/// A reusable list of launch records — shared by the page and the summary panel.
struct RecentList: View {
    let records: [RunRecord]
    var emptyHint: String = "Nothing yet"
    var onRun: ((RunRecord) -> Void)?
    var onDelete: ((RunRecord) -> Void)?

    var body: some View {
        if records.isEmpty {
            Text(emptyHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Spacing.sm)
        } else {
            VStack(spacing: 0) {
                ForEach(records) { record in
                    RecentRow(record: record, onRun: onRun, onDelete: onDelete)
                    if record.id != records.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }
}

private struct RecentRow: View {
    let record: RunRecord
    var onRun: ((RunRecord) -> Void)?
    var onDelete: ((RunRecord) -> Void)?
    @State private var hovering = false
    @State private var deleteHover = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if record.iconImageData == nil, let host = record.faviconHost {
                FaviconView(host: host, size: 32, cornerRadius: 9)
            } else {
                IconTile(
                    iconImageData: record.iconImageData,
                    systemName: record.iconSystemName,
                    colorHex: record.colorHex,
                    size: 32,
                    cornerRadius: 9
                )
            }
            Text(record.tileName).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(Self.format(record.timestamp))
                .font(.caption).foregroundStyle(.secondary)
            if let onDelete, hovering {
                Button { onDelete(record) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: deleteHover ? .semibold : .regular))
                        .foregroundStyle(deleteHover ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        .frame(width: 26, height: 26)
                        .background(deleteHover ? Color.red.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { deleteHover = $0 }
                .help("Remove from history")
            }
            trailingIcon
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            hovering ? Color.black.opacity(0.04) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onRun?(record) }
    }

    @ViewBuilder private var trailingIcon: some View {
        if onRun != nil {
            Image(systemName: hovering ? "play.circle.fill" : "play.circle")
                .font(.system(size: 16))
                .foregroundStyle(hovering ? AnyShapeStyle(Theme.Palette.brand) : AnyShapeStyle(.tertiary))
        } else {
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// "Today, 10:32" / "Yesterday, 17:40" / "12 Jun, 09:20".
    static func format(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today, \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        let day = date.formatted(.dateTime.day().month(.abbreviated))
        return "\(day), \(time)"
    }
}
