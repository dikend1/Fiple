# Change: Harden pairing & remote execution

> Retrospective capture. The work below was implemented across audit-driven fix
> rounds after `add-fiple-mvp`; this change records it through the OpenSpec
> pipeline (proposal → spec deltas → evidence) and cites ADR-0002. It does not
> introduce new unbuilt work.

## Why

A multi-dimension audit of the implemented MVP found that the LAN control channel
trusted any device on the network: a 4-digit code with no brute-force defense, a
session token in plaintext UserDefaults, the Mac executing arbitrary
client-supplied actions, and no limits on inbound connections or buffering. These
let a LAN peer pair by exhausting the code space, read the token from disk, or
have the Mac launch any app / URL / shortcut it chose. This change hardens
pairing and execution against an on-network attacker **without** changing the
plaintext-transport architecture (that trade-off and its limits are recorded in
ADR-0002).

## What Changes

- **Pairing brute-force defense** — a session-global throttle: 5 wrong codes →
  30 s lockout **and code rotation**; typed rejection reasons (`incorrectCode` /
  `tooManyAttempts` / `pairingExpired`) so the remote can distinguish lockout
  from a wrong code.
- **Session token in the Keychain** — device-only storage on both apps, with a
  one-time migration that scrubs the legacy UserDefaults copy.
- **Server-authoritative execution** — the remote sends only ids; `runAction`
  carries an `actionID` and the Mac resolves it against its own Fiple Bar / tiles
  (`ActionLookup`), executing only saved actions. `openURL` is restricted to
  `http`/`https` (`ActionPolicy`); `file://` and custom schemes are rejected.
- **Abuse / DoS limits** — cap on simultaneous inbound connections, a 15 s
  auth-timeout that reaps unauthenticated sockets, and bounded inbound buffering
  (replacing unbounded).
- **Discovery stability** — discovery dedupes each Mac, finishes its stream on
  cancel, and stops/replaces the browser without leaking.
- **Reliability fixes** folded in: listener continuation can't double-resume;
  `connect` has a timeout; "re-run from Recent" works for single actions.

No transport/protocol-architecture change beyond the `runAction` payload (now an
id) and the typed `pairRejected` reason. No TLS/PAKE (see ADR-0002 criteria).

## Impact

- Affected specs: `pairing` (hardening), `tile-execution` (authorization),
  `fiple-bar` (new capability — curated quick actions, previously unspecified).
- Affected code: `FipleKit` (`PairingThrottle`, `ActionPolicy`, `ActionLookup`,
  `Keychain`, transport `FipleServer`/`FipleClient`/`PeerConnection`, `Messages`),
  `Apps/FipleMac/ServerController` + `MacActionExecutor`, `Apps/FipleiOS/RemoteController`.
- Related design docs:
  - docs/design-docs/adr/0002-lan-transport-security-model.md (new — cited)
  - docs/design-docs/adr/0001-local-network-topology.md (amended: transport)
  - docs/design-docs/prd/fiple-pairing.md (resolves the rate-limit open question)
  - docs/architecture/index.md (updated to implemented truth)
