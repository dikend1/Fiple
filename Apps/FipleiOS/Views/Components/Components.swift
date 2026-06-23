import SwiftUI

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
