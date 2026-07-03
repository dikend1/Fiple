# Remote Terminal — Design

**Date:** 2026-07-04
**Status:** draft (pending human acceptance; no implementation until Fiple 1.0 App Store review completes)
**Inspiration:** Macky-style phone→Mac access. Core value chosen: a real terminal (zsh) on iPhone.

## Decisions locked during brainstorming

1. **Core feature:** interactive terminal from iPhone. Screen viewing/control is out of scope (possible later phase).
2. **Distribution:** the Mac host moves to **Developer ID direct distribution** after 1.0 ships. A sandboxed MAS host cannot offer a useful shell. The iOS client stays on the App Store.
3. **Network scope:** LAN-first over the existing paired transport model. Off-LAN P2P (data channel, CloudKit signaling) is Phase 2 with its own design.
4. **Security:** TLS on the terminal channel + a master password (Face ID convenience on iOS). This deliberately revisits ADR-0002's plaintext trade-off — its revision criteria fire (shell access, secrets in traffic).
5. **Terminal depth:** full pty with **SwiftTerm** (MIT) as the iOS renderer — the project's first third-party dependency, recorded per stack policy.

## Architecture choice

Considered: (A) extend the existing JSON tile channel, (B) a separate privileged terminal service, (C) WebRTC from day one. **Chosen: B.**

Rationale: zero regression risk to the freshly approved 1.0 tile path; a binary protocol suited to pty byte streams; a clean seam to swap the transport for P2P in Phase 2; easy to gate as a Pro feature.

## Components

### Mac host — `TerminalService`

- A second `NWListener` (Network.framework) on its own port, **TLS from the first byte**.
- Not advertised via Bonjour. The paired, authenticated tile channel tells the client the terminal port and whether the service is enabled. Unpaired devices never learn the service exists.
- **Off by default.** Cannot be enabled until a master password is set. Absent entirely from any MAS build.
- **PTY engine:** `forkpty` → user's login shell (`zsh -l`, `TERM=xterm-256color`). Host is un-sandboxed (Developer ID), so the shell is a real one.

### Wire protocol (new, binary; lives in `FipleKit/` beside `FrameCodec`)

```
[type: u8][length: u32 BE][payload]
  DATA      — raw pty bytes, both directions
  RESIZE    — cols/rows
  CONTROL   — JSON: auth, attach/detach, exit code, errors
  PING/PONG — keepalive
```

### iOS client

- SwiftTerm `TerminalView` wrapped in `UIViewRepresentable`; keyboard accessory bar (`Esc`, `Ctrl`, `Tab`, arrows, `⌃C`).
- Terminal entry appears on the home screen only when the host reports the service enabled. Tap → Face ID (master password on first use) → full-screen terminal.

## Security model (three layers)

1. **Channel:** TLS on the terminal listener. The host generates a persistent P-256 identity key (self-signed). Its public-key fingerprint is delivered over the existing paired channel; the client **pins** it and verifies during the TLS handshake (`sec_protocol_verify`). No CAs, no manual certs. The identity is reusable for DTLS in Phase 2.
2. **Session auth:** the first CONTROL frame proves the pairing token (already in Keychain) **plus the master password**. The Mac stores only salt + PBKDF2 hash. Failed attempts throttle/lock out, reusing the `harden-pairing-and-execution` pattern.
3. **Convenience:** on iOS the master password is stored in the Keychain behind biometrics after first entry → subsequent terminal entry is Face ID.

ADR-0002 is not superseded for the tile channel; a new ADR introduces a separate class of **privileged channels** that require encryption.

## Session lifecycle (detach/reattach)

iOS kills sockets seconds after the app backgrounds; the shell must survive that.

- A shell **session** on the Mac is independent of the TCP connection. On disconnect the pty keeps running; the host accumulates output in a 256 KB ring buffer.
- A disconnected session survives a **grace period** (default 10 min, configurable on the Mac), then receives `SIGHUP` and closes.
- On reconnect the client sends `CONTROL: attach(sessionID)`; the host replays the buffer; SwiftTerm restores the screen.
- Phase 1: **one active session per paired device.**

**Mac UI (menu bar settings):** Terminal section — enable toggle, set/change master password, grace period, active-session list with terminate.

**Error handling:** wrong password → escalating throttle (as in pairing); expired session → clear "session ended" screen offering a new session; shell exit → show exit code, offer a new session.

## Phasing

- **Phase 0 (now):** documents only. Nothing lands on `main` while 1.0 is in App Store review.
- **Phase 1:** LAN terminal as designed here, shipped in the Developer ID host.
- **Phase 2 (separate design):** off-LAN P2P data channel, CloudKit signaling, transport swapped only beneath `TerminalService`. Reuses the Phase 1 identity keys.

## Governance artifacts to author

- **ADR-0005** — privileged terminal channel (TLS + master password, separate listener; complements ADR-0002).
- **ADR-0006** — Mac host distribution moves to Developer ID (affects sandbox, update mechanism, Shortcuts entitlement).
- **OpenSpec change `add-remote-terminal`** — proposal, tasks, design, `specs/remote-terminal/spec.md` with WHEN/THEN scenarios.
- SwiftTerm recorded as an external dependency in the change's `design.md`/TRD.
- All artifacts stay `draft` until human acceptance, per repo rules.

## Testing

- **FipleKit unit:** binary codec (length edge cases, truncated frames); auth flow (correct/wrong password, throttling).
- **FipleKit loopback:** TLS handshake with pinning (correct key accepted, substituted key rejected).
- **macOS:** pty echo round-trip; detach/reattach with buffer replay.
- **iOS rendering (SwiftTerm):** manual checklist — vim, htop, colors, resize, accessory keys.

## Out of scope (Phase 1)

Screen viewing/control, off-LAN access, multiple concurrent sessions/tabs, tmux-style persistence beyond the grace period, Android/web clients.
