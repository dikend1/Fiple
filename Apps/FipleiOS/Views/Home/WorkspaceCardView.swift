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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TileIcon(
                iconImageData: tile.iconImageData,
                systemName: tile.iconSystemName,
                colorHex: tile.colorHex,
                size: 40
            )
            // A soft coloured drop-shadow lifts the icon off the card without
            // the muddy halo a blurred backing plate created.
            .shadow(color: base.opacity(0.25), radius: 6, y: 3)

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.name)
                        .font(Theme.Typography.cardTitle)
                        .tracking(-0.3)
                        .foregroundStyle(Theme.Palette.label)
                        .lineLimit(1)
                    // Just the count — the contained apps' icons lived here once
                    // and doubled the card's height for information the run
                    // button doesn't need.
                    Text("\(tile.actions.count) action\(tile.actions.count == 1 ? "" : "s")")
                        .font(.fiple(13))
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                runButton
            }
        }
        .padding(Theme.Spacing.lg)
        // A FIXED height, not a minimum: no tile content can stretch the card
        // or, via carousel equalisation, its neighbours.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 124)
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
            .frame(width: 40, height: 40)
            .background(accent.buttonGradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: base.opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(RunButtonStyle())
        .disabled(isRunning)
        .accessibilityLabel(isRunning ? "Running \(tile.name)" : "Run \(tile.name)")
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
