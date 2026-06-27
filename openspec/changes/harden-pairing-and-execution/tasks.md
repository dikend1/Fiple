# Tasks — Harden pairing & remote execution

> Retrospective: tasks were implemented in audit-driven rounds and verified by
> `swift test` (FipleKit) + `xcodebuild` (both schemes). Commit hashes are cited
> where the work is already on `main`; later items are in the working tree pending
> review. Archive this change (and populate `openspec/specs/`) only after the
> related docs reach human `accepted`.

## 1. Implementation

- [x] 1.1 URL allowlist (`ActionPolicy`, `http`/`https` only) enforced in
  `MacActionExecutor.openURL`. — commits `bb1d303`, `3d202af`
- [x] 1.2 Session token moved to Keychain (`Keychain`) on both apps, with
  one-time UserDefaults→Keychain migration. — commits `dd2ad7b`, `2e9f1c8`, `e841676`
- [x] 1.3 Pairing brute-force throttle (`PairingThrottle`): session-global,
  5 attempts → 30 s lockout + code rotation; wired in `ServerController`. —
  commits `bed90bd`, `2e9f1c8`
- [x] 1.4 Typed `PairRejectReason` (`incorrectCode`/`tooManyAttempts`/
  `pairingExpired`) on the wire; remote maps to distinct copy. — commits `4c75c68`, `2e9f1c8`, `e841676`
- [x] 1.5 Reliability: listener continuation double-resume fixed; `connect`
  timeout; "re-run from Recent" for single actions. — commits `5bff102`, `38d1845`, `e841676`
- [x] 1.6 Server-authoritative execution: `runAction(actionID:)` resolved via
  `ActionLookup` against saved Fiple Bar / tiles; unknown id rejected. —
  working tree (pending commit)
- [x] 1.7 DoS / auth-timeout: inbound connection cap with close-decrement,
  15 s auth-timeout, bounded inbound buffering, idempotent `finish`. —
  working tree (pending commit)
- [x] 1.8 Discovery stability: dedupe per Mac, finish stream on `.cancelled`,
  no browser leak on stop/re-entry. — working tree (pending commit)
- [x] 1.9 Docs/governance: ADR-0002 written; `architecture/index.md` updated;
  privacy manifest reviewed (no change needed); this change authored. —
  working tree (pending commit)

## 2. Verification Evidence

| Check | Command / Method | Result |
| --- | --- | --- |
| URL allowlist blocks `file://` / custom schemes | `swift test` (ActionPolicyTests) | ✅ Pass |
| `runAction` resolves saved ids only; foreign app/shortcut id rejected | `swift test` (ActionLookupTests) | ✅ Pass |
| Throttle: 6 wrong attempts across connections → lockout; expiry; reset semantics | `swift test` (PairingThrottleTests) | ✅ Pass |
| Typed `pairRejected` round-trips | `swift test` (ModelCodingTests) | ✅ Pass |
| Connection cap / auth-timeout / slot release after disconnect | `swift test` (TransportLimitsTests) | ✅ Pass |
| Discovery dedupe + stream finishes on cancel + real-Bonjour discovers once | `swift test` (DiscoveryTests) | ✅ Pass |
| Full suite | `cd FipleKit && swift test` | ✅ 42/42, 11 suites |
| Both apps build | `xcodebuild -scheme FipleMac` / `-scheme FipleiOS` | ✅ BUILD SUCCEEDED |
| Keychain migration scrubs plaintext; token never logged | Code review | ✅ Verified |
| Pairing lockout + rotation in real UI flow | Manual on-device | ⏳ Pending real-device re-test |

## 3. Post-acceptance (governance close-out)

- [ ] 3.1 Human sets ADR-0002 (and ADR-0001 amendment) to `accepted`.
- [ ] 3.2 Promote spec deltas into `openspec/specs/{pairing,tile-execution,fiple-bar}/`.
- [ ] 3.3 Archive to `openspec/changes/archive/YYYY-MM-DD-harden-pairing-and-execution/`.
