import FipleKit
import SwiftUI

/// A workspace tile rendered as a softly tinted card (carousel/grid layout),
/// matching the iOS remote's cards so both apps read as one product.
/// Edit and Delete live in the "…" menu; the card surfaces a single Run action.
struct WorkspaceCard: View {
    let tile: Tile
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var accent: Accent { Accent(hex: tile.colorHex) }
    private var base: Color { Color(hex: tile.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                IconTile(
                    iconImageData: tile.iconImageData,
                    systemName: tile.iconSystemName,
                    colorHex: tile.colorHex,
                    size: 50
                )
                Spacer()
                Menu {
                    Button("Edit", action: onEdit)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(tile.name).font(Theme.Font.cardTitle).lineLimit(1)
                Text(tile.subtitle ?? "\(tile.actions.count) actions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 0) {
                StatColumn(value: tile.appCount, label: "Apps")
                statDivider
                StatColumn(value: tile.websiteCount, label: "Websites")
                statDivider
                StatColumn(value: tile.shortcutCount, label: tile.shortcutCount == 1 ? "Shortcut" : "Shortcuts")
                Spacer()
            }

            HStack {
                Spacer()
                Button(action: onRun) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                        Text("Run").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 8)
                    .background(accent.buttonGradient, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: base.opacity(0.4), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Theme.Palette.surface
                accent.cardGradient
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(base.opacity(0.12))
        )
        // Shadow tinted with the workspace colour, like the iOS cards.
        .shadow(color: base.opacity(0.14), radius: 12, y: 4)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(width: 1, height: 28)
            .padding(.horizontal, Theme.Spacing.lg)
    }
}
