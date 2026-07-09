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
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                IconTile(
                    iconImageData: tile.iconImageData,
                    systemName: tile.iconSystemName,
                    colorHex: tile.colorHex,
                    size: 42
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

            // Name + one composition line. The old stat columns and per-card
            // "Launch from your iPhone" footer said the same things again in
            // twice the height — the page subtitle carries the hint once now.
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tile.name).font(Theme.Font.cardTitle).lineLimit(1)
                    Text(composition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .padding(Theme.Spacing.lg)
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

    /// "4 apps · 1 website" — the whole composition in one quiet line.
    private var composition: String {
        var parts: [String] = []
        if tile.appCount > 0 { parts.append("\(tile.appCount) app\(tile.appCount == 1 ? "" : "s")") }
        if tile.websiteCount > 0 { parts.append("\(tile.websiteCount) website\(tile.websiteCount == 1 ? "" : "s")") }
        return parts.isEmpty ? "Empty — add apps or websites" : parts.joined(separator: " · ")
    }
}
