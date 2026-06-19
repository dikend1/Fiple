import SwiftUI

/// Central design tokens for the Mac app. One source of truth for spacing,
/// radii, typography and colour so every view stays visually consistent and the
/// look can be retuned in a single place (see the Workspaces reference design).
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let tile: CGFloat = 14
        static let control: CGFloat = 10
        static let pill: CGFloat = 999
    }

    enum Palette {
        /// Brand green — active sidebar item, primary affordances.
        static let brand = Color(hex: "#34C759")
        /// Light content background behind the cards.
        static let windowBackground = Color(hex: "#F4F5F7")
        /// Card surface and elevated panels.
        static let surface = Color.white
        /// Dark brand sidebar — fixed regardless of system appearance.
        static let sidebar = Color(hex: "#0E1116")
        static let sidebarRaised = Color(hex: "#1A1F27")
        static let sidebarText = Color(hex: "#E5E7EB")
        static let sidebarSecondary = Color(hex: "#8A94A6")
        static let hairline = Color.black.opacity(0.06)
        static let connected = Color(hex: "#34C759")
    }

    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 30, weight: .bold)
        static let cardTitle = SwiftUI.Font.system(size: 21, weight: .bold)
        static let statNumber = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
    }
}

/// Derives the per-accent colours used by an icon tile and a workspace card
/// from a tile's stored hex colour, matching the soft tinted look in the design.
struct Accent {
    let base: Color

    init(hex: String) { base = Color(hex: hex) }
    init(_ color: Color) { base = color }

    /// Soft fill behind the glyph on an icon tile.
    var iconBackground: Color { base.opacity(0.16) }

    /// The glyph / symbol colour itself.
    var glyph: Color { base }

    /// Subtle diagonal wash used as a workspace card background.
    var cardGradient: LinearGradient {
        LinearGradient(
            colors: [base.opacity(0.14), base.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// A standard elevated card: surface fill, rounded corners, hairline border.
    func fipleCard(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.Palette.hairline)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}
