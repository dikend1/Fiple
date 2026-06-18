import Foundation

/// Outcome of a single ``Action`` execution.
public struct ActionResult: Identifiable, Sendable, Equatable, Codable {
    public let actionID: UUID
    public let ok: Bool
    public let error: String?

    public var id: UUID { actionID }

    public init(actionID: UUID, ok: Bool, error: String? = nil) {
        self.actionID = actionID
        self.ok = ok
        self.error = error
    }

    public static func success(_ actionID: UUID) -> ActionResult {
        ActionResult(actionID: actionID, ok: true)
    }

    public static func failure(_ actionID: UUID, _ message: String) -> ActionResult {
        ActionResult(actionID: actionID, ok: false, error: message)
    }
}

/// Aggregated result of running every action in a ``Tile``.
public struct RunResult: Sendable, Equatable, Codable {
    public let tileID: UUID
    public let actions: [ActionResult]

    public init(tileID: UUID, actions: [ActionResult]) {
        self.tileID = tileID
        self.actions = actions
    }

    public var allSucceeded: Bool { actions.allSatisfy(\.ok) }
    public var failures: [ActionResult] { actions.filter { !$0.ok } }
}
