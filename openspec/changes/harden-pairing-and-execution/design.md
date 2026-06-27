# Design — Harden pairing & remote execution

Records the technical decisions behind the hardening. Security rationale and the
accepted residual risk live in `docs/design-docs/adr/0002-lan-transport-security-model.md`.

## Pairing brute-force throttle

- Pure, testable `PairingThrottle` (in `FipleKit`), owned by `ServerController`
  (`@MainActor`) so the counter is **session-global**, shared across every socket —
  reconnecting per guess does not reset it. State clears only on a successful pair
  or an explicit restart of advertising (`start()`/`disconnect()`), never on
  socket close.
- 5 wrong attempts → 30 s lockout. On lockout the code is **rotated**
  (`regenerateCode()`), so any digits guessed so far are worthless, and the
  socket is dropped. Decision: throttle + rotation instead of binding the code to
  a session key cryptographically — adequate against online guessing; the
  eavesdropping/MITM gap is accepted and tracked in ADR-0002.

## Typed rejection reasons

- `pairRejected` carries a `PairRejectReason` enum (`incorrectCode`,
  `tooManyAttempts`, `pairingExpired`) instead of a free-text string, so the
  remote can surface a lockout distinctly. Wire-compatible: encoded as the enum's
  string rawValue; an unknown value decodes to `incorrectCode`.

## Keychain token storage

- `Keychain` wrapper (generic password, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
  device-only/no iCloud). `AfterFirstUnlock` is chosen over `WhenUnlocked` so a
  known phone can reconnect after a reboot. One-time migration reads any legacy
  UserDefaults token, writes it to the Keychain, and removes the plaintext copy
  **only on a successful write**.

## Server-authoritative execution

- `runAction(actionID:)` (was `runAction(Action)`). The Mac resolves the id with
  `ActionLookup.resolve(_:fipleBar:tiles:)` and executes only a **saved** action;
  an unknown id is rejected (and a failure `runResult` is returned so the phone
  clears its spinner). `ActionPolicy.allowsOpening` limits `openURL` to
  `http`/`https`. Net: the Mac never executes a client-supplied payload.

## DoS / auth-timeout limits

- `FipleServer` caps simultaneous inbound connections and decrements via a
  one-shot `PeerConnection.onClose` hook; over-cap connections are cancelled
  before a `PeerConnection` is created.
- `PeerConnection.startAuthTimeout(_:)` closes a socket that has not
  authenticated within 15 s (`ServerController` arms it per connection, cancels it
  on `markAuthenticated()` at accept). `finish()` is idempotent and frees the
  timer/handlers exactly once.
- Inbound `AsyncThrowingStream` uses `.bufferingNewest(64)` instead of unbounded;
  per-frame size already capped at 8 MB.

## Discovery stability

- `discover()` dedupes by service identity (name/type/domain, ignoring interface
  — pure `FipleClient.dedupeKey` seam), finishes the stream on `.cancelled` as
  well as `.failed`, and cancels/replaces the previous browser on re-entry and in
  `stopDiscovery()`.

## Privacy manifest review

- Verified after the token move: both `PrivacyInfo.xcprivacy` declare
  `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`, no tracking, no collected
  data. UserDefaults is still used — for local preferences/identifiers/history
  only (Mac id; Fiple Bar via `PinnedAppsStore`; iOS launch history via
  `LaunchRecord`; legacy-token read-and-remove during migration). The session
  token now lives in the **Keychain**, which is **not** a required-reason API, so
  no manifest entry is needed for it. **Conclusion: the manifest remains accurate;
  no change required.**

## Out of scope

- TLS / PSK / PAKE / Noise — deferred per ADR-0002's move-to-encryption criteria.
- Low-severity transport nits (e.g. `waitUntilReady` ordering, port-0 handling,
  `TileRunner` cancellation, autoclosure logging) — deliberately deferred to keep
  the pre-release diff small.
