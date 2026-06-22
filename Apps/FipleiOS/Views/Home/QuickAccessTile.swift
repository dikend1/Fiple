import FipleKit
import SwiftUI

/// A single Quick Access entry rendered as a soft card: the action's icon over
/// its name, on an elevated white tile. Tapping runs the parent tile on the Mac;
/// while it's launching the icon dims behind a small spinner.
struct QuickAccessTile: View {
    let item: QuickAction
    var isRunning: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            QuickActionIcon(action: item, size: 48, cornerRadius: 13)
                .overlay {
                    if isRunning {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(.ultraThinMaterial)
                        ProgressView().controlSize(.small)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isRunning)

            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, 6)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.Palette.hairline)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

/// A gentle press-scale for tappable tiles — makes the grid feel responsive
/// without a heavy highlight.
struct QuickTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
