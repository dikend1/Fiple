# Fiple MVP — Technical Requirements Document

> type: trd
> status: draft
> date: 2026-06-18
> deciders: []
> relates-to: prd/fiple-pairing.md, prd/fiple-remote-tiles.md

---

## Overview

Fiple MVP is two native apps that talk over the local network: a macOS menu-bar
companion (source of truth + executor + tile management) and an iOS remote (view
+ trigger). The technical shape must stay simple and dependency-light: Apple
frameworks for discovery and transport, a small JSON message protocol, and
on-Mac persistence. The architectural topology decision (local-only, no cloud,
Mac as source of truth) is recorded in `adr/0001-local-network-topology.md`.

---

## Existing Stack

Greenfield project; stack chosen below.

- Framework: SwiftUI (both apps); AppKit bridging on macOS for the menu-bar item
- Language: Swift
- Styling: SwiftUI native
- Backend: none (no cloud) — macOS companion is the local server
- Database: local persistence on Mac (Codable JSON file or SwiftData); none on phone
- Tests: XCTest (unit) + protocol/integration tests on the message layer

---

## Technical Invariants

- **Mac is the only writer** — The phone never mutates tile state; it sends
  triggers and renders snapshots received from the Mac.
- **Local network only** — No connection leaves the LAN. No cloud endpoint, no
  account.
- **Independent actions** — Each action executes and reports independently; one
  failure never aborts the remaining actions in a tile.
- **Single active pairing** — At most one phone is paired/connected to a Mac at a
  time in MVP.
- **Reconnect without re-pairing** — A persisted pairing on the phone reconnects
  automatically until an explicit disconnect.

---

## Data Model

Minimum v1 entities (stored on Mac):

```
Tile
  id: UUID
  name: String
  icon: String        // SF Symbol name or asset ref
  color: String       // hex / named
  order: Int
  actions: [Action]

Action
  id: UUID
  type: enum { launchApp, openURL, openFile }
  // exactly one payload depending on type:
  bundleId: String?   // launchApp
  appPath: String?    // launchApp (fallback)
  url: String?        // openURL
  path: String?       // openFile (file or folder)
  openWithBundleId: String?  // openFile (optional target app)

Pairing (on Mac)
  pairedDeviceId: String?    // last paired phone
  // 4-digit code is ephemeral, not persisted long-term

Pairing (on phone)
  macIdentifier: String      // remembered Mac for auto-reconnect
```

The phone persists only the remembered Mac identifier; tile data is transient
(received from the Mac).

---

## Interfaces

Transport: Bonjour/mDNS for background discovery + WebSocket for the message
channel. Messages are JSON.

| Interface | Input | Output | Owner |
| --- | --- | --- | --- |
| Discovery (Bonjour) | Mac advertises `_fiple._tcp` service | Phone resolves candidate Macs silently | macOS + iOS |
| `pair` | `{ code }` from phone | `{ ok, macId }` or `{ error }` | macOS |
| `tiles.snapshot` | (on connect / on change) | `{ tiles: [Tile] }` pushed to phone | macOS |
| `run` | `{ tileId }` from phone | `{ tileId, results: [{actionId, ok, error?}] }` | macOS |
| `connection.state` | link up/down events | `{ connected: Bool }` on phone | iOS |

---

## Verification Strategy

- [ ] Unit tests: tile/action serialization round-trips (Codable).
- [ ] Unit tests: action executor maps each type to the correct system call
  (`launchApp` → NSWorkspace/`open -a`, `openURL`, `openFile`) and reports
  per-action results including failures.
- [ ] Integration test: pairing handshake accepts a correct code and rejects a
  wrong/expired one.
- [ ] Integration test: `run` executes all actions in order and returns a result
  per action; a forced single-action failure does not abort the rest.
- [ ] Manual: pair two real devices on one Wi-Fi in <30s; trigger a 4-action
  preset; confirm per-action feedback; disconnect and confirm a new code is
  required.

---

## Out Of Scope

- Cloud relay / cross-network transport.
- Window-management (Accessibility API) work.
- Voice/AI intent parsing pipeline (v1.1).
- Multi-phone or multi-Mac fan-out.
- Tile editing UI on the phone.

---

## Open Questions

| Question | Owner | Status |
| --- | --- | --- |
| WebSocket library vs raw `Network.framework` (`NWConnection`) for the channel | maksat | open |
| App Sandbox / hardened-runtime impact on launching arbitrary apps & files | maksat | open |
| Persistence choice: Codable JSON file vs SwiftData on the Mac | maksat | open |
| Handshake crypto: how the 4-digit code is bound to a session key | maksat | open |
