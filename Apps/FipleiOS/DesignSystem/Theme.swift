import SwiftUI
import UIKit

/// Central design tokens for the iOS remote. Mirrors the Mac app's `Theme` so
/// the two apps read as one product — spacing, radii, type and colour live here
/// and nowhere else.
enum Theme {
    enum Spacing {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        /// Small extra bottom inset under tabbed scroll content. iOS 26 already
        /// insets a ScrollView-in-TabView for the floating tab bar automatically,
        /// so this only adds a little breathing room — a larger value (was 96)
        /// just stacked on top of the system inset and left a big empty gap.
        static let tabBarClearance: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 22
        static let tile: CGFloat = 16
        static let control: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Palette {
        /// Brand green — active tab, primary affordances, "Connected" status.
        static let brand = Color(hex: "#2DA44E")
        /// Blue used for inline links / "View all" / the add affordance.
        static let brandLink = Color(hex: "#2F6BFF")
        /// App background behind the cards.
        static let background = Color(hex: "#F4F5F7")
        /// Card / elevated surface.
        static let surface = Color.white
        /// Primary label colour.
        static let label = Color(hex: "#0E1116")
        /// Secondary / supporting text.
        static let secondary = Color(hex: "#8A94A6")
        static let hairline = Color.black.opacity(0.06)
        static let connected = Color(hex: "#2DA44E")
    }

    enum Typography {
        static let cardTitle = Font.fiple(18, .bold)
    }
}

extension Font {
    /// A fixed-point system font that scales with the user's Dynamic Type
    /// setting. Use in place of `.system(size:weight:)` so the mockup's exact
    /// sizes stay authoritative at the default setting while still growing and
    /// shrinking with the accessibility text size.
    static func fiple(
        _ size: CGFloat,
        _ weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight, design: design)
    }
}

/// Derives the soft tinted accent colours for an icon tile / card from a stored
/// hex colour — the same recipe the Mac app uses.
struct Accent {
    let base: Color

    init(hex: String) { base = Color(hex: hex) }

    /// Soft fill behind a glyph.
    var iconBackground: Color { base.opacity(0.16) }
    /// The glyph colour itself.
    var glyph: Color { base }
    /// Subtle diagonal wash used as a workspace card background.
    var cardGradient: LinearGradient {
        LinearGradient(
            colors: [base.opacity(0.18), base.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// A soft radial glow, placed top-leading behind the icon, that gives the
    /// workspace card a single light source instead of a flat wash.
    var cardGlow: RadialGradient {
        RadialGradient(
            colors: [base.opacity(0.28), base.opacity(0)],
            center: .topLeading,
            startRadius: 0,
            endRadius: 240
        )
    }

    /// Solid accent gradient for the primary run button — the card's one bold,
    /// tactile element.
    var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [base.opacity(0.95), base],
            startPoint: .top,
            endPoint: .bottom
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
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}
