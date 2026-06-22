import SwiftUI

/// A circular progress ring with a time read-out in the centre. Pure display —
/// `progress` (0…1) and `time` are passed in; no timer logic lives here.
struct CircularTimer: View {
    let progress: Double
    let time: String
    let caption: String
    var subtitle: String? = nil
    var tint: Color = Color(hex: "#3B82F6")
    var diameter: CGFloat = 260

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text(time)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.label)
                    .monospacedDigit()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(caption)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The compact "Blocked Apps" panel used on the active-session and editor
/// screens: a count and a truncated row of app icons.
struct BlockedAppsPreview: View {
    let apps: [BlockedApp]
    var maxIcons = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Blocked Apps")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.Palette.label)
            Text("\(apps.count) apps blocked")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.secondary)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(apps.prefix(maxIcons)) { app in
                    BrandTile(glyph: app.glyph, size: 38, cornerRadius: 11)
                }
                if apps.count > maxIcons {
                    OverflowChip(count: apps.count - maxIcons, size: 38)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fipleCard()
    }
}

/// A circular transport control (stop / pause / skip) used on the session screen.
struct TransportButton: View {
    let symbol: String
    let label: String
    var prominent: Bool = false
    var tint: Color = Color(hex: "#3B82F6")
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 26 : 18, weight: .bold))
                    .foregroundStyle(prominent ? .white : Theme.Palette.label)
                    .frame(width: prominent ? 76 : 52, height: prominent ? 76 : 52)
                    .background(
                        Circle().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Color.black.opacity(0.05)))
                    )
            }
            .buttonStyle(.plain)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.secondary)
        }
    }
}
