import FipleKit
import SwiftUI

/// A workspace tile rendered as a softly tinted card (carousel/grid layout),
/// matching the iOS remote's cards so both apps read as one product.
///
/// The Mac is where a workspace is *configured*; launching happens from the
/// iPhone. So the card's primary action is Edit (add / change the apps and
/// URLs), not Run — Delete lives in the "…" menu.
struct WorkspaceCard: View {
    let tile: Tile
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
                // Edit is the card's primary button below, so the "…" menu only
                // carries the destructive Delete — no duplicate Edit.
                Menu {
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
                Spacer()
            }

            HStack(spacing: Theme.Spacing.sm) {
                Label("Launch from your iPhone", systemImage: "iphone.gen3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onEdit) {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .bold))
                        Text("Edit").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(base)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 8)
                    .background(base.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(base.opacity(0.22)))
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
