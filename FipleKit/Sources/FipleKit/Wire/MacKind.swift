import Foundation

/// A coarse Mac hardware family, sent to the remote so the connection card can
/// show the right device icon — a laptop drawing for MacBooks, a desktop glyph
/// for an iMac / Mac mini / Mac Studio / Mac Pro. The Mac detects its own family
/// and reports it; the remote never guesses. Defaults to `.laptop` when unknown
/// (the most common case, and the app's original always-a-laptop behaviour).
public enum MacKind: String, Sendable, Codable, Equatable, CaseIterable {
    case laptop
    case iMac
    case macMini
    case macStudio
    case macPro
    case desktop
}
