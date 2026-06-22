import SwiftUI

/// Renders an ``AppGlyph`` as an app-icon placeholder: a brand-coloured tile
/// with a white glyph, so it reads as a real colourful app icon in the compact
/// "blocked apps" rows on the Focus screens.
struct BrandTile: View {
    let glyph: AppGlyph
    var size: CGFloat = 44
    var cornerRadius: CGFloat = Theme.Radius.tile

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(hex: glyph.colorHex))
            .frame(width: size, height: size)
            .overlay(content.foregroundStyle(.white))
    }

    @ViewBuilder private var content: some View {
        switch glyph.symbol {
        case let .sf(name):
            Image(systemName: name)
                .font(.system(size: size * 0.42, weight: .semibold))
        case let .monogram(text):
            Text(text)
                .font(.system(size: size * 0.40, weight: .bold, design: .rounded))
        }
    }
}

/// A rounded glyph tile driven by an SF Symbol + hex colour — the soft tinted
/// look used for workspace / focus icons (matches the Mac `IconTile`).
struct GlyphTile: View {
    let symbol: String
    let colorHex: String
    var size: CGFloat = 52
    var cornerRadius: CGFloat = Theme.Radius.tile

    var body: some View {
        let accent = Accent(hex: colorHex)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(accent.glyph)
            .frame(width: size, height: size)
            .background(accent.iconBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// "+N" overflow chip shown after a truncated row of app icons.
struct OverflowChip: View {
    let count: Int
    var size: CGFloat = 44

    var body: some View {
        Text("+\(count)")
            .font(.system(size: size * 0.30, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Palette.secondary)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
    }
}

/// Section header: bold title with an optional trailing action ("View all", "+").
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}
