# Architecture

> Status: current-state map (MVP slice implemented)

Reflects the implemented Fiple MVP. Updated from build/test evidence per
`docs/architecture/AGENTS.md`. Decisions are explained by
`docs/design-docs/adr/0001-local-network-topology.md` (topology) and
`docs/design-docs/adr/0002-lan-transport-security-model.md` (security model);
capabilities were introduced by `openspec/changes/add-fiple-mvp/` and hardened by
`openspec/changes/harden-pairing-and-execution/`.

## System map

Three Swift modules, no backend, no cloud:

| Module | Kind | Responsibility |
| --- | --- | --- |
| `FipleKit/` | SPM library (macOS + iOS) | Pure, tested core: `Tile`/`Action` model, wire messages + JSON `MessageCodec`, length-prefixed `FrameCodec`, `PairingCode` + `PairingThrottle` (brute-force lockout), `ActionPolicy` (URL allowlist) + `ActionLookup` (server-authoritative id resolution), `Keychain` (token), `TileRunner`/`ActionExecutor`, and Network.framework transport (`PeerConnection`, `FipleServer`, `FipleClient`). |
| `Apps/FipleMac/` | macOS menu-bar app | Source of truth + executor. `TileStore` + `PinnedAppsStore` (Fiple Bar), `ServerController` (advertise, pair/token handshake with throttle/lockout, Keychain token, auth-timeout, snapshot push, server-authoritative run), `MacActionExecutor` (`NSWorkspace`), management UI. |
| `Apps/FipleiOS/` | iOS app | Pure remote. `RemoteController` (silent deduped discovery, code/token auth via Keychain, tiles + Fiple Bar, triggers by id), pairing + tile-grid UI. |

The Xcode project is generated from `project.yml` via **XcodeGen** (not committed).

## Runtime flow

1. Mac `ServerController` starts `FipleServer` → advertises `_fiple._tcp` over
   Bonjour and shows a 4-digit code. Inbound connections are capped; each must
   authenticate within 15 s or it is closed.
2. iOS `RemoteController` discovers the Mac silently (no device list, results
   deduped per Mac) and sends `pair(code)` (first time) or `reconnect(token)`
   (remembered).
3. Pairing is throttled: after 5 wrong codes the Mac locks out for 30 s and
   rotates the code; rejections carry a typed reason (`incorrectCode` /
   `tooManyAttempts` / `pairingExpired`).
4. On accept, the Mac issues a session token (stored in the **Keychain** on both
   sides), sends `paired` + `tilesSnapshot` + `fipleBar`. The phone persists the
   token for silent reconnection.
5. Trigger → `run(tileID)` or `runAction(actionID)`. The Mac is authoritative:
   it resolves the id against its own tiles / Fiple Bar and runs only saved
   actions (`openURL` limited to `http`/`https`); `TileRunner` runs each action
   in order, reporting independently → `runResult`.
6. Explicit disconnect clears the token (Keychain) and regenerates the code;
   transient drops keep both so the phone reconnects silently.

## Transport contract

- Bonjour `_fiple._tcp` for discovery (deduped by service identity);
  `NWConnection`/`NWListener` for the link. **Plaintext TCP — no TLS** (security
  model and residual risks: ADR-0002).
- Wire framing: 4-byte big-endian length prefix + JSON body (`FrameCodec`,
  8 MB cap). Inbound messages are buffered with a bounded policy.
- Messages:
  - `ClientMessage` { `pair(code)`, `reconnect(token)`, `run(tileID)`,
    `runAction(actionID)` } — triggers carry **ids only**; the Mac resolves them.
  - `ServerMessage` { `paired(macID, macName, token)`,
    `pairRejected(reason: PairRejectReason)`, `tilesSnapshot(tiles)`,
    `fipleBar(actions)`, `runResult(result)` }.
- Abuse limits: cap on simultaneous inbound connections; 15 s auth-timeout for
  unauthenticated sockets; pairing brute-force throttle (5 attempts → 30 s
  lockout + code rotation).
- Session token stored in the Keychain (device-only), not UserDefaults.

## Verification

- `cd FipleKit && swift test` — 42 tests across model coding, framing, pairing
  code, **pairing throttle/lockout**, **URL allowlist** (`ActionPolicy`),
  **server-authoritative id resolution** (`ActionLookup`), tile-run semantics,
  real-socket loopback, **connection limits / auth-timeout**, and **discovery
  stability** (dedupe + stream lifecycle, incl. a real-Bonjour test).
- `xcodebuild -project Fiple.xcodeproj -scheme FipleMac` / `-scheme FipleiOS`
  build both apps.

## Privacy

- No tracking, no data collected, nothing leaves the LAN. Both `PrivacyInfo.xcprivacy`
  declare `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` (app-local
  access only). UserDefaults now holds **only** local preferences/identifiers/
  history — Mac id, the Fiple Bar (`PinnedAppsStore`), and launch history (iOS
  `LaunchRecord`); the session **token moved to the Keychain** (no privacy-manifest
  reason required). The manifest remains accurate — no change needed.
