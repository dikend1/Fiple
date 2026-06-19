import FipleKit
import SwiftUI

/// Full launch history page.
struct RecentView: View {
    let recents: RecentStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(title: "Recent", subtitle: "Workspaces you've launched recently.") {
                    if !recents.records.isEmpty {
                        Button("Clear", role: .destructive) { recents.clear() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    RecentList(records: recents.records, emptyHint: "Launch a workspace from your iPhone to see it here.")
                }
                .padding(Theme.Spacing.lg)
                .fipleCard()
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
        }
    }
}

/// A reusable list of launch records — shared by the page and the summary panel.
struct RecentList: View {
    let records: [RunRecord]
    var emptyHint: String = "Nothing yet"

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
                    RecentRow(record: record)
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

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconTile(
                iconImageData: record.iconImageData,
                systemName: record.iconSystemName,
                colorHex: record.colorHex,
                size: 32,
                cornerRadius: 9
            )
            Text(record.tileName).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(Self.format(record.timestamp))
                .font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Spacing.sm)
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
