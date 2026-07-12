import FipleKit
import SwiftUI

/// A single Quick Access entry rendered as a soft card: the action's icon over
/// its name, on an elevated white tile. Tapping runs the parent tile on the Mac;
/// while it's launching the icon dims behind a small spinner.
struct QuickAccessTile: View {
    let item: QuickAction
    var isRunning: Bool = false
    /// Locked behind Fiple Pro — dimmed with a lock; tapping opens the paywall.
    var isLocked: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            QuickActionIcon(action: item, size: 48, cornerRadius: 13)
                .overlay {
                    if isRunning {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(.ultraThinMaterial)
                        ProgressView().controlSize(.small)
                    } else if isLocked {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(.ultraThinMaterial)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isRunning)

            Text(item.title)
                .font(.fiple(12, .medium))
                .foregroundStyle(isLocked ? Theme.Palette.secondary : Theme.Palette.label)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 30, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, 6)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.Palette.hairline)
        )
        .overlay(alignment: .topTrailing) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Theme.Palette.label.opacity(0.85), in: Circle())
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        // Make the WHOLE tile tappable, not just the icon/label. Without this the
        // Button (this tile is its label) only hit-tests the visible content, so
        // taps on the card's padding/empty area were ignored — only the text ran.
        .contentShape(Rectangle())
    }
}

/// An empty placeholder slot that pads a Fiple Bar page out to a full 4×2 grid,
/// so the bar always reads as a complete grid rather than a ragged last row —
/// a faint, glassy outlined tile matching the real tiles' footprint.
struct QuickAccessSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.Palette.surface.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 120)
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
