import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}

enum TilePalette {
    // Brand green (#2DA44E) is first — it's the default workspace colour, so the
    // picker opens with the default swatch selected and leftmost.
    static let swatches = ["#2DA44E", "#3B82F6", "#8B5CF6", "#EF4444", "#F59E0B", "#EC4899", "#0EA5E9", "#64748B"]
}
