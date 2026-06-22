import SwiftUI

/// Focus home: an Active / All / Templates switch, the running session card,
/// and the list of focus presets. Tapping a preset opens its editor; the running
/// card opens the live session. No timer or blocking logic yet — pure UI.
struct FocusListView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case active = "Active", all = "All", templates = "Templates"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .active
    @State private var presets = Sample.focusPresets

    private var activePreset: FocusPreset? { presets.first { $0.isActive } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    scopePicker

                    if let active = activePreset {
                        NavigationLink {
                            FocusSessionView(preset: active)
                        } label: {
                            ActiveSessionCard(preset: active)
                        }
                        .buttonStyle(.plain)
                    }

                    presetList
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Focus")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FocusEditorView(preset: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.Palette.brand)
                    }
                }
            }
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(Scope.allCases) { option in
                let selected = option == scope
                Button {
                    withAnimation(.snappy(duration: 0.2)) { scope = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Theme.Palette.label : Theme.Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm + 2)
                        .background(
                            selected ? AnyView(Capsule().fill(Theme.Palette.surface)
                                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)) : AnyView(Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.05), in: Capsule())
    }

    private var presetList: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(presets) { preset in
                NavigationLink {
                    FocusEditorView(preset: preset)
                } label: {
                    PresetRow(preset: preset)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The large "running now" card: glyph, name, big remaining time, pause button,
/// and the blocked-apps strip.
private struct ActiveSessionCard: View {
    let preset: FocusPreset

    var body: some View {
        let tint = Color(hex: preset.colorHex)
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                GlyphTile(symbol: preset.symbol, colorHex: preset.colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(preset.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.Palette.label)
                        Text("Active")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.brand)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.Palette.brand.opacity(0.14), in: Capsule())
                    }
                    Text("24:37")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.label)
                        .monospacedDigit()
                    Text("Remaining time")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.black.opacity(0.06), lineWidth: 5)
                    Circle().trim(from: 0, to: 0.62)
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 64, height: 64)
            }

            Divider()

            HStack {
                Text("Blocked Apps (\(preset.blockedApps.count))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.secondary)
                Spacer()
                Text("Edit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand)
            }
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(preset.blockedApps.prefix(6)) { app in
                    BrandTile(glyph: app.glyph, size: 34, cornerRadius: 10)
                }
                if preset.blockedApps.count > 6 {
                    OverflowChip(count: preset.blockedApps.count - 6, size: 34)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Accent(hex: preset.colorHex).cardGradient)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.hairline))
    }
}

/// A focus-preset row: glyph, name + subtitle, and a trailing status / duration.
private struct PresetRow: View {
    let preset: FocusPreset

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            GlyphTile(symbol: preset.symbol, colorHex: preset.colorHex, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text(preset.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if preset.isActive {
                Text("Active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand)
            } else {
                Text("\(preset.durationMinutes) min")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
        }
        .padding(Theme.Spacing.lg)
        .fipleCard()
    }
}

#Preview {
    FocusListView()
}
