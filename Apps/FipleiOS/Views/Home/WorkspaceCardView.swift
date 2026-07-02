import FipleKit
import SwiftUI

/// A workspace preset (a multi-action ``Tile``) rendered as a tall gradient card:
/// real icon, name, tagline, a stat row (apps / sites / files) and a Run button
/// that triggers it on the Mac.
struct WorkspaceCardView: View {
    let tile: Tile
    var isRunning: Bool = false
    let onRun: () -> Void

    private var accent: Accent { Accent(hex: tile.colorHex) }
    private var base: Color { Color(hex: tile.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            TileIcon(
                iconImageData: tile.iconImageData,
                systemName: tile.iconSystemName,
                colorHex: tile.colorHex,
                size: 48
            )
            // A crisp coloured drop-shadow lifts the icon off the card without
            // the muddy halo a blurred backing plate created.
            .shadow(color: base.opacity(0.35), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(tile.name)
                    .font(Theme.Typography.cardTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.label)
                Text(tile.subtitle ?? "\(tile.actions.count) actions")
                    .font(.fiple(14))
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.md)

            HStack(alignment: .center) {
                actionIcons
                Spacer(minLength: Theme.Spacing.sm)
                runButton
            }
        }
        .padding(Theme.Spacing.lg)
        // A tighter minimum so short cards don't leave a dead band of empty
        // space in the middle; two cards in a grid row still equalise to the
        // taller one.
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background {
            ZStack {
                Theme.Palette.surface
                accent.cardGradient
                accent.cardGlow
                // A faint glass highlight along the very top edge.
                LinearGradient(
                    colors: [.white.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .frame(maxHeight: .infinity, alignment: .top)
                .blendMode(.softLight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                .blendMode(.overlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(base.opacity(0.12))
        )
        // A shadow tinted with the workspace colour, so each card gently emits
        // its own hue instead of a flat grey drop.
        .shadow(color: base.opacity(0.16), radius: 16, y: 8)
    }

    // MARK: Run button — the card's signature affordance

    private var runButton: some View {
        Button(action: onRun) {
            Group {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.fiple(15, .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1) // optically centre the triangle
                }
            }
            .frame(width: 46, height: 46)
            .background(accent.buttonGradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: base.opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(RunButtonStyle())
        .disabled(isRunning)
        .accessibilityLabel(isRunning ? "Running \(tile.name)" : "Run \(tile.name)")
    }

    /// The real icons of the apps / sites / files this workspace launches, each
    /// in a uniform white chip so a row of mismatched app icons reads as one tidy
    /// set — the at-a-glance "what's inside" preview.
    private var actionIcons: some View {
        let actions = tile.actions
        let maxVisible = 4
        let visible = actions.count > maxVisible ? Array(actions.prefix(3)) : actions
        let overflow = actions.count - visible.count
        return HStack(spacing: 7) {
            ForEach(visible) { action in
                QuickActionIcon(
                    action: QuickAction(action: action, tileID: tile.id),
                    size: 26,
                    cornerRadius: 7
                )
                .padding(5)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.Palette.hairline))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.fiple(13, .semibold, design: .rounded))
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.Palette.hairline))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }
        }
    }
}

/// A tactile press for the run button — a firm scale-down with a touch of dim,
/// so tapping to launch feels like pressing a real key.
private struct RunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
