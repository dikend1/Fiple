import Foundation

// MARK: - Focus UI models
//
// Focus has no real engine yet (no timers, no app blocking, nothing over the
// wire), so these are presentation-only stand-ins. Home / Recent / Settings are
// driven by the live `RemoteController` instead — see those views. Keep these
// dumb: no networking, no persistence, no business logic.

/// A blocked app inside a focus preset.
struct BlockedApp: Identifiable, Hashable {
    let id = UUID()
    let glyph: AppGlyph
}

/// A focus preset / mode (Deep Work, Study Mode…). Logic — timers, real app
/// blocking — is intentionally absent; this only describes how it looks.
struct FocusPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let symbol: String
    let colorHex: String
    let durationMinutes: Int
    var isActive: Bool = false
    var blockedApps: [BlockedApp] = []
}

// MARK: - Seed content (matches the mockups)

enum Sample {
    static let blockedApps: [BlockedApp] = [
        BlockedApp(glyph: AppCatalog.instagram),
        BlockedApp(glyph: AppCatalog.youtube),
        BlockedApp(glyph: AppCatalog.tiktok),
        BlockedApp(glyph: AppCatalog.x),
        BlockedApp(glyph: AppCatalog.telegram),
        BlockedApp(glyph: AppCatalog.reddit),
    ]

    static let focusPresets: [FocusPreset] = [
        FocusPreset(
            name: "Deep Work",
            subtitle: "Block distractions and focus on what matters.",
            symbol: "target", colorHex: "#3B82F6",
            durationMinutes: 25, isActive: true, blockedApps: blockedApps
        ),
        FocusPreset(
            name: "Study Mode",
            subtitle: "Perfect for studying and learning.",
            symbol: "graduationcap.fill", colorHex: "#8B5CF6",
            durationMinutes: 25, blockedApps: Array(blockedApps.prefix(4))
        ),
        FocusPreset(
            name: "Workout",
            subtitle: "Stay focused on your training.",
            symbol: "dumbbell.fill", colorHex: "#FB923C",
            durationMinutes: 45, blockedApps: Array(blockedApps.prefix(3))
        ),
        FocusPreset(
            name: "Personal Time",
            subtitle: "Relax and enjoy your time.",
            symbol: "heart.fill", colorHex: "#EF4444",
            durationMinutes: 90, blockedApps: Array(blockedApps.prefix(5))
        ),
    ]
}
