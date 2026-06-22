import SwiftUI

/// A lightweight visual stand-in for a real app icon, used by the Focus screens'
/// sample "blocked apps". An SF Symbol (or monogram letter) on a brand-coloured
/// tile — swap for real image assets later by touching only `BrandTile`.
struct AppGlyph: Hashable {
    enum Symbol: Hashable {
        case sf(String)       // an SF Symbol name
        case monogram(String) // a 1–2 character fallback
    }

    let name: String
    let symbol: Symbol
    let colorHex: String

    init(_ name: String, sf: String, hex: String) {
        self.name = name
        self.symbol = .sf(sf)
        self.colorHex = hex
    }

    init(_ name: String, monogram: String, hex: String) {
        self.name = name
        self.symbol = .monogram(monogram)
        self.colorHex = hex
    }
}

/// The brands shown as "blocked apps" in the Focus mockups.
enum AppCatalog {
    static let telegram  = AppGlyph("Telegram", sf: "paperplane.fill", hex: "#229ED9")
    static let instagram = AppGlyph("Instagram", sf: "camera.fill", hex: "#E1306C")
    static let youtube   = AppGlyph("YouTube", sf: "play.rectangle.fill", hex: "#FF0000")
    static let tiktok    = AppGlyph("TikTok", sf: "music.note", hex: "#111111")
    static let x         = AppGlyph("X (Twitter)", monogram: "X", hex: "#111111")
    static let reddit    = AppGlyph("Reddit", sf: "antenna.radiowaves.left.and.right", hex: "#FF4500")
}
