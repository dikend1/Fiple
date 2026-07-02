import FipleKit
import SwiftUI
import UIKit

/// Renders a tile's real icon: the PNG streamed from the Mac when present
/// (`iconImageData`), otherwise the soft tinted SF-Symbol glyph. Used for
/// workspace cards and Recent rows.
struct TileIcon: View {
    let iconImageData: Data?
    let systemName: String
    let colorHex: String
    var size: CGFloat = 52
    var cornerRadius: CGFloat = Theme.Radius.tile

    var body: some View {
        if let iconImageData, let image = UIImage(data: iconImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            GlyphTile(symbol: systemName, colorHex: colorHex, size: size, cornerRadius: cornerRadius)
        }
    }
}

/// Icon for a Quick Access action. Websites resolve a real favicon over the
/// network (works on iOS); apps and files fall back to a neutral SF-Symbol tile
/// because their real macOS icons aren't part of the wire snapshot.
struct QuickActionIcon: View {
    let action: QuickAction
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 16

    var body: some View {
        if let iconImageData = action.iconImageData, let image = UIImage(data: iconImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else if let host = action.faviconHost {
            Favicon(host: host, size: size, cornerRadius: cornerRadius, fallbackSymbol: action.fallbackSymbol)
        } else {
            Image(systemName: action.fallbackSymbol)
                .font(.fiple(size * 0.40, .semibold))
                .foregroundStyle(Theme.Palette.label)
                .frame(width: size, height: size)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.Palette.hairline))
        }
    }
}

/// Loads a website favicon via the public favicon service (same source the Mac
/// app uses), with an SF-Symbol fallback while loading or offline.
struct Favicon: View {
    let host: String
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 16
    var fallbackSymbol: String = "globe"

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.Palette.hairline))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(size * 0.22)
                } else {
                    Image(systemName: fallbackSymbol)
                        .font(.fiple(size * 0.38, .semibold))
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
            .frame(width: size, height: size)
            .task(id: host) { image = await FaviconImageCache.shared.icon(for: host) }
    }
}
