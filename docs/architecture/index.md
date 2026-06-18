# Architecture

> Status: current-state map (MVP slice implemented)

Reflects the implemented Fiple MVP. Updated from build/test evidence per
`docs/architecture/AGENTS.md`. Decisions are explained by
`docs/design-docs/adr/0001-local-network-topology.md`; the capability was
introduced by `openspec/changes/add-fiple-mvp/`.

## System map

Three Swift modules, no backend, no cloud:

| Module | Kind | Responsibility |
| --- | --- | --- |
| `FipleKit/` | SPM library (macOS + iOS) | Pure, tested core: `Tile`/`Action` model, wire messages + JSON `MessageCodec`, length-prefixed `FrameCodec`, `PairingCode`, `TileRunner`/`ActionExecutor`, and Network.framework transport (`PeerConnection`, `FipleServer`, `FipleClient`). |
| `Apps/FipleMac/` | macOS menu-bar app | Source of truth + executor. `TileStore` (JSON persistence), `ServerController` (advertise, pair/token handshake, snapshot push, run), `MacActionExecutor` (`NSWorkspace`), management UI. |
| `Apps/FipleiOS/` | iOS app | Pure remote. `RemoteController` (silent discovery, code/token auth, tiles, triggers), pairing + tile-grid UI. |

The Xcode project is generated from `project.yml` via **XcodeGen** (not committed).

## Runtime flow

1. Mac `ServerController` starts `FipleServer` → advertises `_fiple._tcp` over
   Bonjour and shows a 4-digit code.
2. iOS `RemoteController` discovers the Mac silently (no device list) and sends
   `pair(code)` (first time) or `reconnect(token)` (remembered).
3. On accept, the Mac issues a persistent session token, sends `paired` +
   `tilesSnapshot`. The phone persists the token for silent reconnection.
4. Tap → `run(tileID)` → `TileRunner` runs each action in order via
   `MacActionExecutor`; every action reports independently → `runResult`.
5. Explicit disconnect clears the token and regenerates the code; transient
   drops keep both so the phone reconnects silently.

## Transport contract

- Bonjour `_fiple._tcp` for discovery; `NWConnection`/`NWListener` for the link.
- Wire framing: 4-byte big-endian length prefix + JSON body (`FrameCodec`,
  8 MB cap).
- Messages: `ClientMessage` { `pair`, `reconnect`, `run` };
  `ServerMessage` { `paired`, `pairRejected`, `tilesSnapshot`, `runResult` }.

## Verification

- `cd FipleKit && swift test` — 15 tests across model coding, framing, pairing,
  tile-run semantics, and a real-socket loopback.
- `xcodebuild -project Fiple.xcodeproj -scheme FipleMac` / `-scheme FipleiOS`
  build both apps.
