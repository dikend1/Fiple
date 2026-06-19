import FipleKit
import SwiftUI

/// A workspace tile rendered as a rich gradient card (grid layout).
struct WorkspaceCard: View {
    let tile: Tile
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                IconTile(
                    iconImageData: tile.iconImageData,
                    systemName: tile.iconSystemName,
                    colorHex: tile.colorHex,
                    size: 52
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
                Text(tile.name).font(Theme.Font.cardTitle)
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

            HStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Button(action: onEdit) {
                    Text("Edit").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 7)
                        .background(Theme.Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
                }
                .buttonStyle(.plain)

                Button(action: onRun) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                        Text("Run").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 7)
                    .background(Color(hex: tile.colorHex), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent(hex: tile.colorHex).cardGradient)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.hairline))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(width: 1, height: 28)
            .padding(.horizontal, Theme.Spacing.lg)
    }
}
