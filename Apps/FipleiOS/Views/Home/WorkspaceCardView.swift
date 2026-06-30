import FipleKit
import SwiftUI

/// A workspace preset (a multi-action ``Tile``) rendered as a tall gradient card:
/// real icon, name, tagline, a stat row (apps / sites / files) and a Run button
/// that triggers it on the Mac.
struct WorkspaceCardView: View {
    let tile: Tile
    var isRunning: Bool = false
    /// Locked behind Fiple Pro — greyed, badged, and the action opens the paywall.
    var isLocked: Bool = false
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            TileIcon(
                iconImageData: tile.iconImageData,
                systemName: tile.iconSystemName,
                colorHex: tile.colorHex,
                size: 48
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(tile.name)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.label)
                Text(tile.subtitle ?? "\(tile.actions.count) actions")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            actionIcons
        }
        .opacity(isLocked ? 0.5 : 1)
        .overlay(alignment: .bottomTrailing) { runButton }
        .overlay(alignment: .topTrailing) { if isLocked { proBadge } }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(Accent(hex: tile.colorHex).cardGradient)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.hairline))
    }

    /// Run (free) or unlock (locked → paywall). Stays tappable when locked.
    private var runButton: some View {
        Button(action: onRun) {
            Group {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.secondary)
                } else if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hex: tile.colorHex))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: tile.colorHex))
                }
            }
            .frame(width: 40, height: 40)
            .background(
                (isLocked ? Theme.Palette.secondary : Color(hex: tile.colorHex)).opacity(0.18),
                in: Circle()
            )
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel(
            isLocked ? "Unlock \(tile.name) with Fiple Pro"
                     : (isRunning ? "Running \(tile.name)" : "Run \(tile.name)")
        )
    }

    /// Small "PRO" lock chip in the corner of a locked card.
    private var proBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
            Text("PRO").font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.Palette.label.opacity(0.85), in: Capsule())
    }

    /// The real icons of the apps / sites / files this workspace launches, shown
    /// as a compact row with a "+N" chip for the overflow — the at-a-glance "what's
    /// inside" preview from the mockup, in place of raw stat counts.
    private var actionIcons: some View {
        let actions = tile.actions
        let maxVisible = 4
        let visible = actions.count > maxVisible ? Array(actions.prefix(3)) : actions
        let overflow = actions.count - visible.count
        return HStack(spacing: 6) {
            ForEach(visible) { action in
                QuickActionIcon(
                    action: QuickAction(action: action, tileID: tile.id),
                    size: 30,
                    cornerRadius: 8
                )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(height: 30)
                    .padding(.horizontal, 8)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
