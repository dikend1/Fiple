import Foundation
import Testing
@testable import FipleKit

/// Records execution order and fails any action whose id is in `failing`.
private actor MockExecutor: ActionExecutor {
    private(set) var executed: [UUID] = []
    let failing: Set<UUID>

    init(failing: Set<UUID> = []) { self.failing = failing }

    func execute(_ action: Action) async -> ActionResult {
        executed.append(action.id)
        return failing.contains(action.id)
            ? .failure(action.id, "simulated failure")
            : .success(action.id)
    }

    var order: [UUID] { executed }
}

@Suite("Tile runner")
struct TileRunnerTests {
    private func tile(_ actions: [Action]) -> Tile {
        Tile(name: "Test", actions: actions)
    }

    @Test("Runs every action in declared order")
    func runsInOrder() async {
        let actions = (0..<4).map { _ in Action(kind: .launchApp(bundleID: "x")) }
        let mock = MockExecutor()
        let result = await TileRunner(executor: mock).run(tile(actions))

        #expect(result.actions.map(\.actionID) == actions.map(\.id))
        #expect(await mock.order == actions.map(\.id))
        #expect(result.allSucceeded)
    }

    @Test("A failing action does not abort the rest")
    func failureDoesNotAbort() async {
        let a = Action(kind: .launchApp(bundleID: "ok1"))
        let b = Action(kind: .openFile(path: "/missing", openWith: nil))
        let c = Action(kind: .openURL(URL(string: "https://ok.com")!))
        let mock = MockExecutor(failing: [b.id])

        let result = await TileRunner(executor: mock).run(tile([a, b, c]))

        #expect(await mock.order == [a.id, b.id, c.id]) // all three ran
        #expect(result.actions.count == 3)
        #expect(result.failures.map(\.actionID) == [b.id])
        #expect(!result.allSucceeded)
    }

    @Test("Empty tile yields an empty, successful result")
    func emptyTile() async {
        let result = await TileRunner(executor: MockExecutor()).run(tile([]))
        #expect(result.actions.isEmpty)
        #expect(result.allSucceeded)
    }
}
