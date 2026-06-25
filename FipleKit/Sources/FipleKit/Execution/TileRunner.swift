import Foundation

/// Executes a single ``Action`` on the host. Platform implementations live in
/// the Mac app (e.g. via `NSWorkspace`); tests inject a mock.
public protocol ActionExecutor: Sendable {
    func execute(_ action: Action) async -> ActionResult
}

/// Runs all actions of a tile in order.
///
/// Invariant: every action runs and reports independently — a single failure
/// never aborts the remaining actions (see PRD/spec `tile-execution`).
public struct TileRunner: Sendable {
    private let executor: ActionExecutor

    public init(executor: ActionExecutor) {
        self.executor = executor
    }

    public func run(_ tile: Tile) async -> RunResult {
        FipleLog.execution.info("running tile '\(tile.name)' (\(tile.actions.count) action(s))")
        var results: [ActionResult] = []
        results.reserveCapacity(tile.actions.count)
        for action in tile.actions {
            results.append(await executor.execute(action))
        }
        let result = RunResult(tileID: tile.id, actions: results)
        let ok = results.filter(\.ok).count
        FipleLog.execution.info("tile '\(tile.name)' done: \(ok)/\(results.count) ok")
        return result
    }
}
