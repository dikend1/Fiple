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

            stats

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
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(Accent(hex: tile.colorHex).cardGradient)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.hairline))
    }

    private var stats: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if tile.appCount > 0 { stat(tile.appCount, "Apps") }
            if tile.websiteCount > 0 { stat(tile.websiteCount, "Web") }
            if tile.shortcutCount > 0 { stat(tile.shortcutCount, tile.shortcutCount == 1 ? "File" : "Files") }
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.label)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.secondary)
        }
    }
}
