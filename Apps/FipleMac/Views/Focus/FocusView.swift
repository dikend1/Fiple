import SwiftUI

/// Full Focus page: every focus mode with its toggle.
struct FocusView: View {
    let focus: FocusStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(title: "Focus", subtitle: "Quick modes for how you want to work.")

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(focus.modes) { mode in
                        FocusToggleRow(mode: mode) { focus.toggle(mode.id) }
                    }
                }
                .padding(Theme.Spacing.lg)
                .fipleCard()

                Text("Focus modes remember their state. Automatic actions (silencing notifications, launching apps) are coming soon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
        }
    }
}

/// A focus mode row with an icon, copy, and a binding-free toggle.
struct FocusToggleRow: View {
    let mode: FocusMode
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconTile(iconImageData: nil, systemName: mode.iconSystemName, colorHex: mode.colorHex, size: 34, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(mode.name).font(.system(size: 14, weight: .semibold))
                Text(mode.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { mode.isOn }, set: { _ in onToggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.Palette.connected)
        }
    }
}
