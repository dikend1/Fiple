import Foundation

/// Resolves a remote `runAction(actionID:)` request to a *saved* action.
///
/// The remote only sends an id; the Mac executes the action it finds in its own
/// Fiple Bar or tiles. An id that the Mac never sent (or that has since been
/// removed) resolves to `nil` and the request is rejected — so a paired peer
/// can never have the Mac launch an arbitrary app, shortcut, or URL it supplies
/// itself. The returned action's payload (bundle id / shortcut name / URL) is
/// always the saved one, never anything the client could influence.
public enum ActionLookup {
    /// Finds the saved action with `id` in the Fiple Bar first, then across all
    /// tiles. Returns `nil` if no saved action matches.
    public static func resolve(_ id: UUID, fipleBar: [Action], tiles: [Tile]) -> Action? {
        if let action = fipleBar.first(where: { $0.id == id }) { return action }
        for tile in tiles {
            if let action = tile.actions.first(where: { $0.id == id }) { return action }
        }
        return nil
    }
}
