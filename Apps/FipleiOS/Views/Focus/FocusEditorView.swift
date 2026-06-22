import SwiftUI

/// Create / edit a focus preset: name, duration, blocked apps and block mode,
/// with a Start button at the bottom. State is local and presentation-only.
struct FocusEditorView: View {
    /// `nil` when creating a new preset.
    let preset: FocusPreset?

    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int
    @State private var blockMode = true
    @State private var blockedApps: [BlockedApp]
    @State private var startSession = false

    private let quickDurations = [15, 25, 50, 60]

    init(preset: FocusPreset?) {
        self.preset = preset
        _minutes = State(initialValue: preset?.durationMinutes ?? 25)
        _blockedApps = State(initialValue: preset?.blockedApps ?? Sample.blockedApps)
    }

    private var name: String { preset?.name ?? "New Focus" }
    private var symbol: String { preset?.symbol ?? "target" }
    private var colorHex: String { preset?.colorHex ?? "#3B82F6" }
    private var tint: Color { Color(hex: colorHex) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                header
                durationCard
                blockedCard
                blockModeCard
                startButton
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 7)
                    .background(Theme.Palette.brand, in: Capsule())
            }
        }
        .navigationDestination(isPresented: $startSession) {
            FocusSessionView(preset: preset ?? Sample.focusPresets[0])
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            GlyphTile(symbol: symbol, colorHex: colorHex, size: 64)
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Palette.label)
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.secondary)
            }
            Text("Block distractions and focus on what matters.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: Duration

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Label("Duration", systemImage: "clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.label)

            HStack(spacing: Theme.Spacing.sm) {
                DurationField(value: minutes / 60, unit: "h")
                DurationField(value: minutes % 60, unit: "min", highlighted: true, tint: tint)
                DurationField(value: 0, unit: "sec")
            }

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(quickDurations, id: \.self) { value in
                    chip(label: value == 60 ? "1h" : "\(value) min", selected: minutes == value) {
                        minutes = value
                    }
                }
                chip(label: "Custom", selected: !quickDurations.contains(minutes)) {}
            }
        }
        .padding(Theme.Spacing.lg)
        .fipleCard()
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .white : Theme.Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.black.opacity(0.05)))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Blocked apps

    private var blockedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Label("Blocked Apps", systemImage: "lock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Spacer()
                Text("Edit")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand)
            }

            VStack(spacing: 0) {
                ForEach(Array(blockedApps.enumerated()), id: \.element.id) { index, app in
                    HStack(spacing: Theme.Spacing.md) {
                        Button {
                            blockedApps.removeAll { $0.id == app.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color(hex: "#EF4444"))
                        }
                        .buttonStyle(.plain)

                        BrandTile(glyph: app.glyph, size: 30, cornerRadius: 9)
                        Text(app.glyph.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Palette.label)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
                    }
                    .padding(.vertical, Theme.Spacing.sm + 2)
                    if index < blockedApps.count - 1 {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .fipleCard()
    }

    // MARK: Block mode

    private var blockModeCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Block Mode")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text("When focus is active, these apps will be blocked completely.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $blockMode)
                .labelsHidden()
                .tint(Theme.Palette.brand)
        }
        .padding(Theme.Spacing.lg)
        .fipleCard()
    }

    private var startButton: some View {
        Button {
            startSession = true
        } label: {
            HStack(spacing: 8) {
                Text("Start Focus Session")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
    }
}

/// One unit of the duration stepper (hh / mm / ss).
private struct DurationField: View {
    let value: Int
    let unit: String
    var highlighted = false
    var tint: Color = Color(hex: "#3B82F6")

    var body: some View {
        HStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(highlighted ? tint : Theme.Palette.label)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(highlighted ? tint.opacity(0.12) : Color.black.opacity(0.04))
        )
    }
}

#Preview {
    NavigationStack { FocusEditorView(preset: Sample.focusPresets[0]) }
}
