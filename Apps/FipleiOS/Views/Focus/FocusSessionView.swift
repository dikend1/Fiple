import SwiftUI

/// The live focus session: a large circular timer, the blocked-apps panel, a
/// motivational line, and transport controls. Timer values are static for now;
/// the controls are visual stand-ins until the focus engine is built.
struct FocusSessionView: View {
    let preset: FocusPreset

    @Environment(\.dismiss) private var dismiss
    @State private var showBlocked = false

    private var tint: Color { Color(hex: preset.colorHex) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                presetChip

                CircularTimer(
                    progress: 0.62,
                    time: "24:37",
                    caption: "Focus Session",
                    subtitle: "of \(preset.durationMinutes):00",
                    tint: tint
                )
                .padding(.top, Theme.Spacing.sm)

                BlockedAppsPreview(apps: preset.blockedApps)

                quote

                controls
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(
            LinearGradient(
                colors: [tint.opacity(0.08), Theme.Palette.background],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.label)
                        .frame(width: 36, height: 36)
                        .fipleCard(cornerRadius: Theme.Radius.control)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showBlocked = true } label: {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.label)
                        .frame(width: 36, height: 36)
                        .fipleCard(cornerRadius: Theme.Radius.control)
                }
            }
        }
        .fullScreenCover(isPresented: $showBlocked) {
            FocusBlockedView(preset: preset)
        }
    }

    private var presetChip: some View {
        HStack(spacing: 8) {
            Image(systemName: preset.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(preset.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.label)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .fipleCard(cornerRadius: Theme.Radius.pill)
    }

    private var quote: some View {
        Text("\u{201C}Focus is not about doing more,\nit's about doing what matters.\u{201D}")
            .font(.system(size: 14, weight: .medium))
            .italic()
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Palette.secondary)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .fipleCard()
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
            TransportButton(symbol: "stop.fill", label: "Stop") { dismiss() }
            TransportButton(symbol: "pause.fill", label: "", prominent: true, tint: tint) {}
            TransportButton(symbol: "forward.fill", label: "Skip 5 min") {}
        }
        .padding(.top, Theme.Spacing.sm)
    }
}

#Preview {
    NavigationStack { FocusSessionView(preset: Sample.focusPresets[0]) }
}
