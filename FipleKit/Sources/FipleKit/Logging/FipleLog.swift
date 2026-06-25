import Foundation
import os

/// Centralised logging for Fiple.
///
/// One subsystem (`com.fiple`) with a fixed set of categories, so logs can be
/// filtered live in **Console.app** while a device is attached:
///
///     subsystem:com.fiple                  // everything
///     subsystem:com.fiple category:pairing // just the handshake
///
/// Both apps and the shared kit log through these, so a single trace shows the
/// whole flow: discovery → connection → pairing → execution.
///
/// Privacy note: this is a local-only, no-cloud tool, so messages are logged
/// `.public` to stay readable in Console. Don't log anything you wouldn't want a
/// person reading the device's logs to see (the values here are bundle ids,
/// URLs, and the local 4-digit pairing code — all already visible on screen).
public enum FipleLog {
    public static let subsystem = "com.fiple"

    /// Bonjour: advertising the Mac, browsing for it from the phone.
    public static let discovery = FipleLogger(category: "discovery")
    /// `PeerConnection` lifecycle and framing (ready / failed / cancelled).
    public static let connection = FipleLogger(category: "connection")
    /// The code/token handshake and reconnect logic.
    public static let pairing = FipleLogger(category: "pairing")
    /// Running tiles and individual actions on the Mac.
    public static let execution = FipleLogger(category: "execution")
}

/// Thin wrapper over `os.Logger` that logs messages `.public` so they're
/// readable in Console. Use the shared instances on ``FipleLog``.
public struct FipleLogger: Sendable {
    private let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: FipleLog.subsystem, category: category)
    }

    /// Verbose, dev-only detail (per-frame, per-message). Hidden unless enabled.
    public func debug(_ message: @autoclosure () -> String) {
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }

    /// Normal flow events worth seeing in a trace.
    public func info(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("\(text, privacy: .public)")
    }

    /// Notable but non-error events (kept in the default log store).
    public func notice(_ message: @autoclosure () -> String) {
        let text = message()
        logger.notice("\(text, privacy: .public)")
    }

    /// Failures and unexpected states.
    public func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .public)")
    }
}
