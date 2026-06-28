import FipleKit
import SwiftUI

/// A workspace preset (a multi-action ``Tile``) rendered as a tall gradient card:
/// real icon, name, tagline, a stat row (apps / sites / files) and a Run button
/// that triggers it on the Mac.
struct WorkspaceCardView: View {
    let tile: Tile
    var isRunning: Bool = false
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

            HStack {
                Spacer()
                Button(action: onRun) {
                    Group {
                        if isRunning {
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
                    .background(Color(hex: tile.colorHex).opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .accessibilityLabel(isRunning ? "Running \(tile.name)" : "Run \(tile.name)")
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(Accent(hex: tile.colorHex).cardGradient)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.hairline))
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
