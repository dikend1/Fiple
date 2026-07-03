# Remote Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iPhone a real interactive shell on the Mac over an encrypted, master-password-gated LAN channel, without touching the shipped 1.0 tile path.

**Architecture:** A separate privileged `TerminalService` on the Mac host — a second `NWListener` with TLS from the first byte, a binary frame protocol tuned for pty byte streams, pinned self-signed identity, and a detach/reattach session that survives iOS backgrounding. The iOS client renders with SwiftTerm. LAN-only in Phase 1; off-LAN P2P is a separate future design.

**Tech Stack:** Swift 6.3 / Xcode 26, Network.framework (TLS via `sec_protocol`), `forkpty`, SwiftTerm (MIT — first third-party dependency), CryptoKit (P-256 identity, PBKDF2). No backend.

## Global Constraints

- **Governance gate is human-only.** `accepted` status is never set by an agent. Every artifact here stays `draft`. Copy this verbatim into each doc's status line: `status: draft`.
- **No code lands on `main` until Fiple 1.0 clears App Store review.** Phase 0 (Tasks 1–4) is documents only. Phase 1 (Tasks 5+) does not begin until the human confirms 1.0 approval AND accepts ADR-0005, ADR-0006, and the OpenSpec change.
- **ADR numbering:** next free numbers are 0005 and 0006 (0003 reserved, 0004 taken). Follow `docs/design-docs/adr/_template.md`.
- **Every OpenSpec requirement needs ≥1 `#### Scenario:`** written `WHEN` / `THEN`. Spec deltas use `## ADDED Requirements`.
- **Toolchain:** Swift 6 language mode, complete strict concurrency. New code lives in `FipleKit/` with unit + loopback tests (`cd FipleKit && swift test`).
- **Dependency policy:** SwiftTerm must be recorded in the OpenSpec change's `design.md` before it is added to `project.yml`.
- **Binary frame format (authoritative — every task uses this):** `[type: u8][length: u32 big-endian][payload]`. Types: `DATA=0x01`, `RESIZE=0x02`, `CONTROL=0x03`, `PING=0x04`, `PONG=0x05`. `CONTROL` payload is UTF-8 JSON.
- **Terminal service is off by default** and cannot be enabled until a master password is set. It is absent from any MAS (sandboxed) build.

---

## Phase 0 — Governance artifacts (executable now)

### Task 1: ADR-0005 — Privileged terminal channel

**Files:**
- Create: `docs/design-docs/adr/0005-privileged-terminal-channel.md`

**Interfaces:**
- Produces: the accepted-security posture that the OpenSpec change (Task 3) and Phase 1 code cite. Establishes the term "privileged channel."

- [ ] **Step 1: Write the ADR** following `_template.md`. Required content:
  - **Context:** ADR-0002 ratified plaintext LAN transport for curated, server-resolved tile execution, and named explicit criteria to move to encryption. A phone→Mac shell trips criterion 2 ("execution surface grows beyond curated, server-resolved tiles/actions — arbitrary … script execution") and criterion 5 ("before broadening … a v1.1-class release"). This ADR does not change the tile channel; it introduces a *separate* privileged channel that requires encryption.
  - **Decision:** (1) Terminal runs on its own `NWListener`, TLS from the first byte, never plaintext. (2) Server identity is a persistent self-signed P-256 key; its SPKI fingerprint is delivered over the already-authenticated tile channel and pinned by the client (`sec_protocol_verify`). No CA, no TOFU window past first pair. (3) Session auth requires the existing pairing token **plus** a master password (PBKDF2 salt+hash stored on the Mac; never transmitted in reverse). (4) Failed password attempts reuse the `harden-pairing-and-execution` throttle/lockout pattern. (5) The service is off by default, requires a master password to enable, and is absent from sandboxed builds.
  - **Alternatives Considered:** reuse plaintext tile channel (rejected — secrets in output); TLS without master password (rejected — a sniffed/persisted token would grant full shell); PAKE from a short code (rejected for Phase 1 — the master password already provides the second factor and is reused off-LAN).
  - **Consequences:** encryption + key-pinning machinery added but scoped to one channel; ADR-0002 unchanged for tiles; a clean seam (the P-256 identity) for Phase 2 DTLS; the Mac host must leave the sandbox (see ADR-0006).
  - **Acceptance:** human-accept checkbox unchecked; cite the OpenSpec change `add-remote-terminal`; note this complements (does not supersede) ADR-0002.

- [ ] **Step 2: Verify header block** — status line reads `> status: draft`, `type: adr`, date `2026-07-04`, title `ADR-0005: Privileged Terminal Channel`.

- [ ] **Step 3: Commit**

```bash
git add docs/design-docs/adr/0005-privileged-terminal-channel.md
git commit -m "docs(adr): 0005 privileged terminal channel (draft)"
```

### Task 2: ADR-0006 — Mac host moves to Developer ID distribution

**Files:**
- Create: `docs/design-docs/adr/0006-mac-host-developer-id-distribution.md`

**Interfaces:**
- Produces: the accepted distribution decision that unblocks a non-sandboxed shell. Task 3's proposal cites it.

- [ ] **Step 1: Write the ADR** following `_template.md`. Required content:
  - **Context:** A useful shell (brew, git, user projects) needs filesystem and process access the MAS sandbox forbids. The 1.0 host ships via MAS; the terminal feature forces a distribution decision.
  - **Decision:** After 1.0, the Mac host is distributed **direct via Developer ID + notarization** (single host binary, not two). The iOS client stays on the App Store and remains the monetization surface. The terminal feature exists only in the Developer ID build.
  - **Alternatives Considered:** stay in MAS with a sandboxed shell (rejected — shell sees only the app container, near-useless, plus review risk); two host versions, MAS-tiles + direct-terminal (rejected — double support/build surface, user confusion); keep host in MAS and put terminal logic in a separate helper (rejected — same sandbox limits, more moving parts).
  - **Consequences (call out the materiality):** need Developer ID signing + notarization + a stapled download; an update mechanism outside MAS (e.g. Sparkle-class or in-app update check) becomes a follow-up decision; the Shortcuts apple-events temporary exception (see memory `fiple-shortcuts-sandbox`) is no longer an App Store review risk once outside MAS; hardened runtime entitlements replace sandbox entitlements.
  - **Acceptance:** human-accept checkbox unchecked; cross-reference ADR-0005.

- [ ] **Step 2: Verify header block** — `> status: draft`, `type: adr`, date `2026-07-04`.

- [ ] **Step 3: Commit**

```bash
git add docs/design-docs/adr/0006-mac-host-developer-id-distribution.md
git commit -m "docs(adr): 0006 Mac host Developer ID distribution (draft)"
```

### Task 3: OpenSpec change `add-remote-terminal` — proposal + design

**Files:**
- Create: `openspec/changes/add-remote-terminal/proposal.md`
- Create: `openspec/changes/add-remote-terminal/design.md`

**Interfaces:**
- Consumes: ADR-0005 (Task 1), ADR-0006 (Task 2).
- Produces: the change scaffold that `spec.md` (Task 4) and Phase 1 tasks reference.

- [ ] **Step 1: Write `proposal.md`** in the analog's shape (`add-remote-file-access/proposal.md`):
  - **Header note:** "New (not-yet-implemented) work. Blocked on human acceptance of **ADR-0005** and **ADR-0006**, and on Fiple 1.0 clearing App Store review. Do not implement until accepted."
  - **Why:** the Macky-style "run a command / check a build from my phone" need; LAN-first because at home you value it least when you're beside the Mac — but it validates the terminal UX before the harder off-LAN phase.
  - **What Changes:** `TerminalService` (second TLS listener, off by default); binary terminal protocol in `FipleKit`; P-256 pinned identity; master-password auth with throttle; pty engine (`forkpty` → `zsh -l`); detach/reattach session with a 256 KB ring buffer and configurable grace period; iOS SwiftTerm terminal screen with Face ID entry and a keyboard accessory bar; Mac menu-bar Terminal settings (enable, password, grace period, active sessions).
  - **Impact:** new capability spec `remote-terminal`; affected code `FipleKit` (protocol/codec, TLS, auth, session model), `Apps/FipleMac` (`TerminalService`, pty, settings), `Apps/FipleiOS` (terminal screen, SwiftTerm wrapper); new dependency **SwiftTerm**; new distribution track (ADR-0006); related docs ADR-0005, ADR-0006, design `docs/superpowers/specs/2026-07-04-remote-terminal-design.md`.

- [ ] **Step 2: Write `design.md`** — technical decisions:
  - The binary frame format (copy the Global Constraints block verbatim).
  - Identity/pinning: P-256 self-signed, SPKI SHA-256 fingerprint delivered over the tile channel, `sec_protocol_verify` on both ends.
  - Auth handshake: first `CONTROL` frame `{op:"auth", token, passwordProof}`; server replies `{op:"auth-ok", sessionID}` or `{op:"auth-fail", reason}`; reasons `badToken` / `badPassword` / `lockedOut`.
  - Session model: pty survives disconnect; ring buffer replay on `{op:"attach", sessionID}`; `SIGHUP` after grace period; one session per device.
  - **Dependency record:** SwiftTerm (MIT), pinned to a specific tag, iOS renderer only; rationale — writing an xterm emulator is months of edge cases; SwiftTerm is used by La Terminal / Secure Shellfish.
  - Reference `openspec validate add-remote-terminal --strict` as the gate once the CLI is available.

- [ ] **Step 3: Commit**

```bash
git add openspec/changes/add-remote-terminal/proposal.md openspec/changes/add-remote-terminal/design.md
git commit -m "openspec(add-remote-terminal): proposal + design (draft)"
```

### Task 4: OpenSpec change `add-remote-terminal` — spec + tasks

**Files:**
- Create: `openspec/changes/add-remote-terminal/specs/remote-terminal/spec.md`
- Create: `openspec/changes/add-remote-terminal/tasks.md`

**Interfaces:**
- Consumes: Task 3 proposal/design.
- Produces: the WHEN/THEN capability contract Phase 1 verifies against.

- [ ] **Step 1: Write `spec.md`** with `## ADDED Requirements`. Each requirement needs ≥1 `#### Scenario:` in WHEN/THEN form. Required requirements:
  - **Requirement: Encrypted, pinned terminal channel** — SHALL run TLS from the first byte on a dedicated listener with a pinned self-signed server identity.
    - Scenario: correct pinned key → WHEN the client connects and the server presents the pinned identity THEN the TLS handshake completes and the session proceeds.
    - Scenario: substituted key → WHEN a server presents an identity whose fingerprint does not match the pinned value THEN the client aborts before sending the token or password proof.
  - **Requirement: Master-password session authentication** — SHALL require pairing token + master password; failed attempts throttle and lock out.
    - Scenario: valid credentials → WHEN token and password proof are correct THEN the server returns `auth-ok` with a session id.
    - Scenario: wrong password → WHEN the password proof is wrong THEN the server returns `auth-fail(badPassword)` and increments the throttle.
    - Scenario: lockout → WHEN the failed-attempt threshold is exceeded THEN further attempts return `auth-fail(lockedOut)` until the cool-off passes.
  - **Requirement: Service disabled by default** — SHALL be off until explicitly enabled, and cannot be enabled without a master password set; absent from sandboxed builds.
    - Scenario: no password set → WHEN the user tries to enable the service without a master password THEN enabling is refused with a prompt to set one.
    - Scenario: default off → WHEN the host launches for the first time THEN the terminal port is not listening and the phone shows no terminal entry.
  - **Requirement: Interactive pty shell** — SHALL spawn the user's login shell and stream bytes both directions; SHALL apply `RESIZE`.
    - Scenario: echo round-trip → WHEN the client sends `echo hello\n` THEN it receives `hello` in the output stream.
    - Scenario: resize → WHEN the client sends a `RESIZE` with new cols/rows THEN the pty window size updates and full-screen apps reflow.
  - **Requirement: Detach and reattach across backgrounding** — the session SHALL survive disconnect for a grace period and replay buffered output on reattach.
    - Scenario: reattach replays → WHEN the client disconnects, output is produced, and the client reattaches within the grace period THEN it receives the buffered output and a live session.
    - Scenario: grace expiry → WHEN no client reattaches before the grace period ends THEN the shell receives `SIGHUP` and the session closes.
  - **Requirement: One session per device** — a paired device SHALL have at most one active terminal session.
    - Scenario: second attach supersedes → WHEN a device with a live session opens a new session THEN the prior session is replaced, not duplicated.

- [ ] **Step 2: Write `tasks.md`** — a `## 0. Gate` section (human-accept ADR-0005, ADR-0006; 1.0 App Store approval; SwiftTerm added to `project.yml`) followed by unchecked sections mirroring Phase 1 Tasks 5–11 below. All boxes `- [ ]`.

- [ ] **Step 3: Validate (if CLI available)**

```bash
openspec validate add-remote-terminal --strict
```
Expected: PASS, or skip with a note if the CLI is not installed.

- [ ] **Step 4: Commit**

```bash
git add openspec/changes/add-remote-terminal/specs openspec/changes/add-remote-terminal/tasks.md
git commit -m "openspec(add-remote-terminal): spec + tasks (draft)"
```

### Task 5: Phase 0 gate checkpoint (STOP)

- [ ] **Step 1:** Confirm all six documents exist and are committed: ADR-0005, ADR-0006, proposal, design, spec, tasks.
- [ ] **Step 2:** Present them to the human for review. **Do not proceed to Phase 1.**
- [ ] **Step 3:** Record the two blocking conditions in the response: (a) human acceptance of ADR-0005/0006 + the change, (b) Fiple 1.0 cleared App Store review. Phase 1 begins only when both are true.

---

## Phase 1 — Code (GATED: do not start until Task 5 conditions are met)

> The tasks below are TDD. Tests live in `FipleKit/Tests`. Follow existing `FrameCodec` tests as the pattern. Do not begin until the human confirms the gate.

### Task 6: Terminal frame codec (FipleKit)

**Files:**
- Create: `FipleKit/Sources/FipleKit/Wire/TerminalFrame.swift`
- Test: `FipleKit/Tests/FipleKitTests/TerminalFrameTests.swift`

**Interfaces:**
- Produces:
  - `enum TerminalFrameType: UInt8 { case data=1, resize=2, control=3, ping=4, pong=5 }`
  - `struct TerminalFrame { let type: TerminalFrameType; let payload: Data }`
  - `enum TerminalFrameCodec { static func encode(_ frame: TerminalFrame) -> Data; static func decode(from buffer: inout Data) throws -> TerminalFrame? }`
  - `enum TerminalFrameError: Error { case unknownType(UInt8); case overflow }`
- Consumes: nothing (mirrors existing `FrameCodec` conventions, 8 MB length cap).

- [ ] **Step 1: Write failing test** — round-trip a `.data` frame; decode returns `nil` on a partial buffer; `decode` throws `unknownType` for byte `0x09`; a length over the 8 MB cap throws `overflow`.

```swift
func testDataFrameRoundTrip() throws {
    let frame = TerminalFrame(type: .data, payload: Data("hello".utf8))
    var buffer = TerminalFrameCodec.encode(frame)
    let decoded = try TerminalFrameCodec.decode(from: &buffer)
    XCTAssertEqual(decoded?.type, .data)
    XCTAssertEqual(decoded?.payload, Data("hello".utf8))
    XCTAssertTrue(buffer.isEmpty)
}

func testPartialBufferReturnsNil() throws {
    var buffer = TerminalFrameCodec.encode(TerminalFrame(type: .data, payload: Data("hi".utf8)))
    buffer.removeLast()
    XCTAssertNil(try TerminalFrameCodec.decode(from: &buffer))
}

func testUnknownTypeThrows() {
    var buffer = Data([0x09, 0,0,0,0])
    XCTAssertThrowsError(try TerminalFrameCodec.decode(from: &buffer))
}
```

- [ ] **Step 2: Run — expect FAIL** (`swift test --filter TerminalFrameTests`), "cannot find 'TerminalFrame'".
- [ ] **Step 3: Implement** `TerminalFrame.swift` — 1-byte type + 4-byte BE length + payload; enforce the 8 MB cap; `decode` consumes from `inout Data` only when a full frame is present.
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Commit** `feat(FipleKit): terminal binary frame codec`.

### Task 7: Master-password proof + throttle (FipleKit)

**Files:**
- Create: `FipleKit/Sources/FipleKit/Terminal/MasterPassword.swift`
- Test: `FipleKit/Tests/FipleKitTests/MasterPasswordTests.swift`

**Interfaces:**
- Produces:
  - `struct MasterPasswordRecord: Codable { let salt: Data; let hash: Data; let iterations: Int }`
  - `enum MasterPassword { static func make(_ password: String) -> MasterPasswordRecord; static func verify(_ password: String, against: MasterPasswordRecord) -> Bool }`
  - Reuse the existing pairing throttle type for lockout — reference it by its real name once located; do not fork a second throttle.
- Consumes: CryptoKit (PBKDF2 via `CommonCrypto` bridge or CryptoKit HKDF-equivalent; use PBKDF2-HMAC-SHA256).

- [ ] **Step 1: Write failing test** — `verify` true for the right password, false for the wrong one; two `make` calls on the same password yield different salts/hashes.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** with a random 16-byte salt and ≥100k iterations.
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Locate the existing pairing throttle** (`grep -rn "Throttle" FipleKit/Sources`) and add a test that terminal auth reuses it; wire lockout. Commit `feat(FipleKit): master-password proof + reuse pairing throttle`.

### Task 8: TLS identity + pinning (FipleKit)

**Files:**
- Create: `FipleKit/Sources/FipleKit/Terminal/TerminalIdentity.swift`
- Test: `FipleKit/Tests/FipleKitTests/TerminalIdentityTests.swift`

**Interfaces:**
- Produces:
  - `struct TerminalIdentity { let p256: P256.Signing.PrivateKey; var fingerprint: Data /* SHA-256 of SPKI */ }`
  - `enum TerminalTLS { static func serverParameters(_ id: TerminalIdentity) -> NWParameters; static func clientParameters(pinning fingerprint: Data) -> NWParameters }`
- Consumes: Network.framework `sec_protocol`, CryptoKit.

- [ ] **Step 1: Write failing test** — `fingerprint` is stable across two reads of the same identity; a different identity yields a different fingerprint.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** identity + `sec_protocol_options_set_verify_block` comparing the presented leaf's SPKI SHA-256 against the pinned value.
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Add a loopback test** — `NWListener` with the identity + `NWConnection` pinning the correct fingerprint completes; pinning a wrong fingerprint fails to connect. Commit `feat(FipleKit): TLS identity + fingerprint pinning`.

### Task 9: PTY session + detach/reattach (Apps/FipleMac)

**Files:**
- Create: `Apps/FipleMac/Terminal/PTYSession.swift`
- Create: `Apps/FipleMac/Terminal/TerminalService.swift`
- Test: `FipleKit/Tests/FipleKitTests/RingBufferTests.swift` (pull the ring buffer into FipleKit so it is unit-testable)
- Create: `FipleKit/Sources/FipleKit/Terminal/ScrollbackBuffer.swift`

**Interfaces:**
- Produces:
  - `final class ScrollbackBuffer { init(capacity: Int); func append(_ d: Data); func snapshot() -> Data }` (256 KB default, drops oldest)
  - `final class PTYSession { init(shell: String) throws; func write(_ d: Data); func resize(cols: Int, rows: Int); var onOutput: (Data) -> Void; func hangup() }`
  - `final class TerminalService` — owns the `NWListener` (TLS via Task 8), authenticates (Task 7), spawns/attaches one `PTYSession` per device, applies grace-period `SIGHUP`.
- Consumes: Tasks 6, 7, 8; `forkpty` from Darwin.

- [ ] **Step 1: Write failing `ScrollbackBuffer` test** — appending beyond capacity keeps the last `capacity` bytes; `snapshot` returns them in order.
- [ ] **Step 2: Run — expect FAIL.** Implement. Run — expect PASS. Commit `feat(FipleKit): scrollback ring buffer`.
- [ ] **Step 3: Implement `PTYSession`** with `forkpty`, `zsh -l`, `TERM=xterm-256color`; output pumped to `onOutput`.
- [ ] **Step 4: Manual pty echo check** — a small host harness writes `echo hello\n`, asserts `hello` in output. Record evidence in `tasks.md`.
- [ ] **Step 5: Implement `TerminalService`** — accept, TLS, auth, attach/detach, grace timer. Commit `feat(FipleMac): TerminalService + pty session with detach/reattach`.

### Task 10: iOS terminal client (Apps/FipleiOS)

**Files:**
- Modify: `project.yml` (add SwiftTerm package — only after design.md records it)
- Create: `Apps/FipleiOS/Terminal/TerminalConnection.swift`
- Create: `Apps/FipleiOS/Terminal/TerminalScreen.swift`
- Create: `Apps/FipleiOS/Terminal/SwiftTermView.swift`

**Interfaces:**
- Consumes: Tasks 6, 7, 8; SwiftTerm `TerminalView`.
- Produces: a `TerminalScreen` SwiftUI view reachable from Home only when the host reports the service enabled.

- [ ] **Step 1: Add SwiftTerm** to `project.yml`, pinned to a tag; `xcodegen generate`; confirm the iOS scheme builds.
- [ ] **Step 2: Implement `TerminalConnection`** — connect with pinned params, run the auth handshake, bridge `DATA` frames ↔ SwiftTerm feed, send `RESIZE` on layout change, reattach on foreground.
- [ ] **Step 3: Wrap** SwiftTerm `TerminalView` in `UIViewRepresentable` (`SwiftTermView`); add the keyboard accessory bar (`Esc`, `Ctrl`, `Tab`, arrows, `⌃C`).
- [ ] **Step 4: Gate entry** behind Face ID (master password on first use, stored in Keychain behind biometrics).
- [ ] **Step 5: Build** the iOS scheme; commit `feat(FipleiOS): SwiftTerm terminal client with Face ID entry`.

### Task 11: Mac settings UI + wiring (Apps/FipleMac)

**Files:**
- Modify: the menu-bar settings view (locate the existing settings surface)
- Modify: the tile-channel handler to advertise the terminal port + enabled flag + identity fingerprint to paired clients

**Interfaces:**
- Consumes: `TerminalService` (Task 9).
- Produces: user-facing enable toggle, master-password set/change, grace-period control, active-session list with terminate.

- [ ] **Step 1: Add a Terminal settings section** — toggle disabled until a master password is set; setting a password uses Task 7.
- [ ] **Step 2: Advertise** the terminal port, enabled flag, and identity fingerprint over the existing authenticated tile channel (new tile-channel control message; do not change existing message semantics).
- [ ] **Step 3: Active-session list** with a terminate action calling `PTYSession.hangup()`.
- [ ] **Step 4: Build** the macOS scheme; manual end-to-end check (enable, pair, open terminal on phone, run a command, background the phone, reopen, confirm reattach). Record evidence in `tasks.md`.
- [ ] **Step 5: Commit** `feat(FipleMac): terminal settings + client discovery wiring`.

### Task 12: Post-implementation governance close-out

- [ ] **Step 1:** Update `docs/architecture/` from code evidence (implemented truth only).
- [ ] **Step 2:** Fill verification evidence in `tasks.md`; check its non-gate boxes.
- [ ] **Step 3:** On human acceptance, move the change to `openspec/changes/archive/YYYY-MM-DD-add-remote-terminal/` and populate `openspec/specs/remote-terminal/`.
- [ ] **Step 4:** Commit `docs: archive add-remote-terminal, update architecture`.

---

## Self-Review

- **Spec coverage:** design §Architecture→Tasks 6–11; §Security 3 layers→Tasks 7 (password/throttle), 8 (TLS/pinning), plus Keychain-biometrics in Task 10 §4; §Session lifecycle→Task 9 (buffer, grace, reattach) + Task 10 §2 (foreground reattach); §Mac UI→Task 11; §Governance→Tasks 1–4, 12; §Testing→tests in Tasks 6–9. SwiftTerm dependency recorded before use (Task 3 §2 / Task 10 §1). Covered.
- **Gate integrity:** Phase 0 (Tasks 1–4) is docs-only and executable now; Task 5 is an explicit STOP; Phase 1 (Tasks 6–12) is gated on human acceptance + 1.0 approval. Matches the Global Constraints.
- **Type consistency:** `TerminalFrameType`/`TerminalFrame`/`TerminalFrameCodec` (Task 6) reused in Tasks 9–10; `MasterPasswordRecord` (Task 7) consistent; `TerminalIdentity.fingerprint` (Task 8) reused in Tasks 10–11; `ScrollbackBuffer` (Task 9) named consistently. `SIGHUP`, grace period, one-session-per-device consistent across spec (Task 4) and code (Task 9).
- **Open item (intentional, not a placeholder):** the existing pairing-throttle type name is resolved by `grep` in Task 7 §5 rather than guessed, to avoid inventing a symbol.
