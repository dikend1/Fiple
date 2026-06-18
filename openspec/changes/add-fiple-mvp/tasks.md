## 1. Implementation

- [ ] 1.1 Scaffold workspace: macOS companion target, iOS remote target, shared
  model/protocol module; confirm SwiftUI + Swift stack.
- [ ] 1.2 Define shared model + JSON protocol (`Tile`, `Action`, messages: `pair`,
  `tiles.snapshot`, `run`, `connection.state`) with Codable round-trip tests.
- [ ] 1.3 Mac: Bonjour advertising (`_fiple._tcp`) + WebSocket server + 4-digit
  code generation and pairing handshake.
- [ ] 1.4 iOS: silent Bonjour discovery + code entry field + pair handshake +
  persisted Mac for auto-reconnect + honest connection-state UI.
- [ ] 1.5 Mac: tile persistence + tile management UI (create/edit/reorder/delete,
  installed-app picker, URL/file actions).
- [ ] 1.6 Mac: action executor for `launchApp` / `openURL` / `openFile` with
  independent per-action result reporting.
- [ ] 1.7 iOS: render tile grid from `tiles.snapshot`, one-tap `run`, show
  per-action success/failure.
- [ ] 1.8 Add/update tests and run verification; record evidence below.

## 2. Verification Evidence

| Check | Command / Method | Result |
| --- | --- | --- |
| Model/protocol serialization round-trips | XCTest | Pending |
| Pairing accepts correct code, rejects wrong/expired | Integration test | Pending |
| `run` executes all actions in order; one failure does not abort rest | Integration test | Pending |
| Action executor maps each type to correct system call | XCTest | Pending |
| Pair 2 real devices on one Wi-Fi <30s; trigger 4-action preset; disconnect → new code | Manual | Pending |
