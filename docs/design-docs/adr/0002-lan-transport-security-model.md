# ADR-0002: LAN Transport Security Model (Plaintext + Pairing Throttle)

> type: adr
> status: draft
> date: 2026-06-27
> deciders: []

---

## Context

ADR-0001 fixed a local-network, no-cloud topology and stated that "the 4-digit
code must be bound to a session key so off-network actors cannot brute-force it."
That cryptographic binding was **not** built. Instead, the implemented MVP
defends pairing with a runtime throttle and rotates the code, keeps the transport
in cleartext, and makes the Mac authoritative over what executes. This posture
was shipped across several commits without an ADR, so the actual security model —
and the risks it accepts — is undocumented. We capture it here, name the residual
risks, and set explicit criteria for when an encrypted transport becomes
required. This amends ADR-0001's transport item (WebSocket → Network.framework)
and resolves its "code bound to a session key" point as **deferred** (below).

This ADR does **not** propose changing the transport now; it ratifies the current
model for the MVP and defines the trigger to revisit it.

---

## Decision

Adopt, for the MVP, the following LAN transport security model:

1. **Transport: plaintext TCP over Network.framework.** `NWListener`/
   `NWConnection`, length-prefixed JSON frames (`FrameCodec`, 8 MB cap). No TLS,
   no channel encryption, no server-identity verification.
2. **Pairing defense by throttle + rotation, not crypto.** A uniformly random
   4-digit code; `PairingThrottle` allows 5 wrong attempts (shared across all
   sockets in the session), then locks out for 30 s **and rotates the code**, so
   accumulated guesses are worthless. Rejections carry a typed reason
   (`incorrectCode` / `tooManyAttempts` / `pairingExpired`).
3. **Session token = bearer credential in the Keychain.** A random UUID issued at
   first pair, stored device-only (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
   not iCloud-synced), used for silent reconnect. It is transmitted in cleartext
   on the LAN and persists until an explicit disconnect.
4. **Server-authoritative execution.** The phone sends only ids
   (`run(tileID:)`, `runAction(actionID:)`); the Mac resolves them against its own
   tiles / Fiple Bar and executes only saved actions. `openURL` is constrained to
   `http`/`https` by `ActionPolicy`. The Mac never executes a client-supplied
   action payload.
5. **Abuse/DoS limits.** Cap on simultaneous inbound connections, a 15 s
   auth-timeout that reaps unauthenticated sockets, and bounded inbound buffering.

This is accepted as adequate for the MVP **threat model: a single trusted,
personal/home Wi-Fi network**, no accounts, no cloud.

---

## Alternatives Considered

Current (accepted) vs. future encrypted-transport options:

| Option | Pros | Cons |
| --- | --- | --- |
| **Plaintext + throttle/rotation (current)** | Zero crypto/cert complexity; ships now; defeats online code guessing | No confidentiality: token/commands sniffable; MITM/Bonjour impersonation possible; injection on an open session |
| **TLS + pinned self-signed cert (TOFU)** | Encrypts channel; authenticates server on reconnect after first trust | First connection is trust-on-first-use (MITM window at pairing); cert lifecycle to manage |
| **TLS + PSK / key derived from pairing code** | Code both authenticates *and* bootstraps an encrypted, MITM-resistant channel; no accounts | Must derive/exchange the PSK from the short code carefully; key rotation on re-pair |
| **PAKE (e.g. SPAKE2) → session key** | Strong: short code yields a high-entropy mutually-authenticated key; no eavesdropper/MITM gain | Most implementation effort; no first-party Apple API — hand-rolled or vendored crypto |

---

## Consequences

- **Easier now:** no certificate or key-exchange machinery; the smallest stack
  that demonstrates the MVP (per the stack-selection policy).
- **Accepted risks (documented, not mitigated):**
  - *Passive sniffing* on a shared L2 segment captures the session token once →
    **persistent** remote control until the user disconnects.
  - *MITM / Bonjour impersonation*: the phone auto-reconnects and sends the token
    to an impostor advertising the same service name.
  - *Wire injection* of `run`/`runAction` into an established TCP session.
  - Severity: **Medium** on a trusted home LAN; **High → Critical** on shared or
    hostile Wi-Fi (office, café, dorm).
- **Constrained:** the product must be positioned/used on a trusted personal LAN
  for the initial release. Moving to an encrypted transport later is a **breaking
  wire change** requiring coordinated app updates and a superseding ADR.

### Criteria to move to an encrypted transport

Adopt encryption (preferred target: **TLS with a key derived from the pairing
code** — PAKE or PSK) when **any** of the following holds:

1. Usage extends beyond a single trusted personal/home LAN (enterprise, office,
   shared, or public Wi-Fi) — including any marketing that invites such use.
2. The execution surface grows beyond curated, server-resolved tiles/actions
   (e.g. arbitrary file or script execution), raising token blast radius.
3. Any cross-network / relay / NAT-traversal feature is planned (needs a new ADR
   regardless; fold encryption in then).
4. App Store review or external security feedback flags the plaintext channel.
5. Before broadening the user base beyond trusted early adopters (a "v1.1"-class
   release).

Until a trigger fires, the throttle + rotation + Keychain + server-authoritative
execution model stands.

---

## Acceptance

- [ ] Human accepted (ratifies the MVP posture and the move-to-encryption criteria).
- [ ] Related OpenSpec change (`harden-pairing-and-execution`) cites this ADR.
- [ ] ADR-0001 amended/cross-referenced for the transport (WebSocket → Network.framework)
      and the deferred "code bound to session key" point.
- [ ] Architecture docs reflect the implemented security controls.
