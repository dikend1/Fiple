## 1. Implementation

> Transport decision revised from the TRD open question: **Network.framework**
> (`NWListener`/`NWConnection`) with length-prefixed JSON framing instead of
> WebSocket — no built-in WS server on Apple platforms and no dependency needed
> on a LAN. Auto-reconnect implemented via a persistent session token
> (`reconnect(token:)`) issued at first pair.

- [x] 1.1 Scaffold workspace: `FipleKit` SPM core + `FipleMac` + `FipleiOS`
  targets via XcodeGen (`project.yml`). SwiftUI + Swift 6 strict concurrency.
- [x] 1.2 Shared model + JSON protocol (`Tile`, `Action`, `ClientMessage`,
  `ServerMessage`, framing) with Codable round-trip tests.
- [x] 1.3 Mac: Bonjour advertising (`_fiple._tcp`) + `NWListener` server +
  4-digit code generation + pairing/token handshake (`ServerController`).
- [x] 1.4 iOS: silent Bonjour discovery + code entry + pair/reconnect handshake
  + persisted token for auto-reconnect + honest connection-state UI.
- [x] 1.5 Mac: tile persistence (JSON) + management UI (create/edit/reorder/
  delete, installed-app picker, URL/file actions).
- [x] 1.6 Mac: `MacActionExecutor` for `launchApp`/`openURL`/`openFile` with
  independent per-action result reporting (`NSWorkspace`).
- [x] 1.7 iOS: tile grid from `tilesSnapshot`, one-tap `run`, per-tile run status.
- [x] 1.8 Tests + builds run; evidence below.

## 2. Verification Evidence

| Check | Command / Method | Result |
| --- | --- | --- |
| Model/protocol serialization round-trips | `swift test` (FipleKit) | ✅ Pass |
| Frame codec: split/coalesced/oversized frames | `swift test` (FrameCodecTests) | ✅ Pass |
| Pairing code validation + random well-formedness | `swift test` (PairingCodeTests) | ✅ Pass |
| `run` executes all actions in order; one failure does not abort rest | `swift test` (TileRunnerTests) | ✅ Pass |
| Framed messages round-trip over a real socket | `swift test` (TransportLoopbackTests) | ✅ Pass — 15/15 |
| FipleMac builds | `xcodebuild -scheme FipleMac` | ✅ BUILD SUCCEEDED |
| FipleiOS builds | `xcodebuild -scheme FipleiOS` (iOS Simulator) | ✅ BUILD SUCCEEDED |
| Pairing accept-correct / reject-wrong code | `ServerController` logic (app target) | ⏳ Manual — verified by build; no app-target test yet |
| Pair 2 real devices on one Wi-Fi <30s; trigger 4-action preset; disconnect → new code | Manual on-device | ⏳ Pending real devices |
