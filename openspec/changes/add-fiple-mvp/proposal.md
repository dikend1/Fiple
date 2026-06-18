# Change: Add Fiple MVP (iPhone remote + Mac companion)

## Why

Knowledge workers lose context after every interruption, manually reopening apps,
URLs, and files to rebuild a working state. Fiple restores that state in one tap
from the phone. This change delivers the first user-visible slice: pair a phone
and Mac on the same Wi-Fi, manage tiles on the Mac, and trigger them from the
phone. Tied to `brd/fiple-mvp.md` and its PRDs.

## What Changes

- Add a macOS menu-bar companion app (SwiftUI) that stores tiles, advertises over
  Bonjour, shows a 4-digit pairing code, and executes tile actions.
- Add an iOS remote app (SwiftUI) that pairs by code, renders the Mac's tile
  grid, triggers tiles, and shows connection + per-action status.
- Add a local WebSocket + JSON message protocol (`pair`, `tiles.snapshot`,
  `run`, `connection.state`).
- Add tile management UI on the Mac (create/edit/reorder/delete; pick from
  installed apps; set URL/file actions).
- Add action execution for `launchApp`, `openURL`, `openFile` with per-action
  result reporting.

## Impact

- Affected specs: `pairing`, `tile-management`, `tile-execution`
- Affected code: new — macOS companion target, iOS remote target, shared model +
  protocol module (exact files unknown until scaffold)
- Related design docs:
  - docs/design-docs/brd/fiple-mvp.md
  - docs/design-docs/prd/fiple-pairing.md
  - docs/design-docs/prd/fiple-remote-tiles.md
  - docs/design-docs/trd/fiple-mvp.md
  - docs/design-docs/adr/0001-local-network-topology.md
