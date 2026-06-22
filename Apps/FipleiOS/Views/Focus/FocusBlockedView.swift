import SwiftUI

/// The full-screen "this app is blocked" interstitial shown when a blocked app
/// is opened during a focus session. Dark, calm, with a skip / end choice.
struct FocusBlockedView: View {
    let preset: FocusPreset

    @Environment(\.dismiss) private var dismiss

    /// The app being blocked — first in the preset's list for this mock.
    private var blocked: AppGlyph { preset.blockedApps.first?.glyph ?? AppCatalog.instagram }
    private var tint: Color { Color(hex: preset.colorHex) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#1A1530"), Color(hex: "#0E1116")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                BrandTile(glyph: blocked, size: 96, cornerRadius: 24)
                    .shadow(color: Color(hex: blocked.colorHex).opacity(0.4), radius: 24, y: 8)

                VStack(spacing: Theme.Spacing.md) {
                    (Text(blocked.name).fontWeight(.bold) + Text("\nis blocked ").fontWeight(.bold))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("You're in \(preset.name) focus mode.\nYou can unblock it after the session\nor skip for 5 minutes.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                sessionCard

                Spacer()

                actions
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var sessionCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GlyphTile(symbol: preset.symbol, colorHex: preset.colorHex, size: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("24:37")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("Remaining")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle().trim(from: 0, to: 0.62)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 64, height: 64)
        }
        .padding(Theme.Spacing.lg)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Color.white.opacity(0.08)))
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button { dismiss() } label: {
                HStack(spacing: 8) {
                    Text("Skip for 5 minutes")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.lg)
                .background(tint.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(tint.opacity(0.6)))
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                HStack(spacing: 8) {
                    Text("End Focus Session")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color(hex: "#FF453A"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.lg)
                .background(Color(hex: "#FF453A").opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Label("Why is this blocked?", systemImage: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
}

#Preview {
    FocusBlockedView(preset: Sample.focusPresets[0])
}
