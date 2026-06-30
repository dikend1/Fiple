# ADR-0003: Monetization Entitlement Dependency (RevenueCat + App Store)

> type: adr
> status: draft
> date: 2026-06-30
> deciders: []

---

## Context

ADR-0001 fixed a **local-network, no-cloud** topology: the remote-control data
path runs entirely over the LAN with no accounts, no backend, no external
service. That decision is about the *control path* — discovery, pairing, tile
snapshots, and execution.

We now want a revenue model (see the tile-paywall PRD): the Mac authors tiles for
free and without limit; the phone runs the first 8 tiles free and unlocks the
rest with **Fiple Pro** (Yearly subscription or Lifetime one-time). Charging on
Apple platforms is only possible through **StoreKit / the App Store**, and we
want managed entitlement resolution and restore without writing our own
receipt-validation server — pointing at **RevenueCat**.

Both are cloud services. This appears to conflict with ADR-0001's "no cloud," so
the dependency must be ratified, scoped, and bounded by an ADR before any code.

This ADR does **not** change the LAN control path. It carves out a separate,
isolated cloud dependency used **only** for monetization.

---

## Decision

1. **Add a monetization-only cloud dependency.** The iOS app talks to the App
   Store (StoreKit 2) for purchases and to **RevenueCat** for entitlement
   resolution and restore. RevenueCat is the receipt-validation backend; we run
   no first-party server.
2. **Scope is strictly monetization.** The dependency carries entitlement state
   only (`pro` active/inactive) and purchase/restore traffic. **No tile data, no
   Mac/phone pairing data, no LAN traffic, and no user content** ever leaves the
   device through it. ADR-0001's no-cloud guarantee continues to hold for the
   entire control path.
3. **iOS-only.** The macOS companion gains **no** new dependency and remains
   fully offline/LAN. Entitlement is read and enforced only by the phone.
4. **Gate is a UX control, not a security boundary.** Client-side entitlement
   checks are acceptable because a bypass only unlocks tiles the user already owns
   on their own Mac — there is no shared secret or server-side content to protect
   (consistent with the ADR-0002 threat model).
5. **Graceful degradation.** A previously-Pro user is never downgraded to locked
   because RevenueCat/App Store is unreachable; the last cached entitlement is
   honored offline. The core free experience works with no network to the
   monetization services at all.

This amends **ADR-0001's no-cloud item** to read: *the control path is cloud-free;
monetization may use App Store + RevenueCat under the constraints above.*

---

## Alternatives Considered

| Option | Pros | Cons |
| --- | --- | --- |
| **RevenueCat + StoreKit 2 (chosen)** | No receipt server to build/operate; managed entitlements, restore, offerings, analytics; cross-device restore; free under current revenue | Adds a third-party cloud + SDK; first external dependency in the repo; vendor lock-in for entitlement state |
| **StoreKit 2 only, on-device** | Zero third-party dependency; closest to no-cloud ethos; on-device receipt verification | Client-only entitlement (weaker anti-piracy); we hand-roll restore/offerings/analytics; no managed cross-device truth |
| **Own backend for receipt validation** | Full control; server-side truth | Build + operate a server — violates the stack-minimalism policy; most effort for least MVP value |
| **No paywall (stay free)** | Keeps strict no-cloud; simplest | No revenue model |

---

## Consequences

- **Easier:** ship a paywall without building/operating a billing backend;
  managed restore and entitlement caching; room to add Monthly/trials later with
  no architecture change.
- **Harder / constrained:**
  - First third-party dependency enters the repo (RevenueCat SDK on iOS) — must
    be recorded in the TRD and `project.yml`.
  - A network dependency now exists for *purchase and first entitlement
    resolution* (not for the free core loop).
  - Entitlement truth is partly vendor-hosted (RevenueCat) — vendor lock-in for
    that slice; mitigated by it being a thin `pro` boolean we could re-home.
  - Privacy/App Store: subscription requires Terms & Privacy, Restore, and
    clear renewal disclosure.

### Criteria to revisit

- Revenue exceeds RevenueCat's free tier → evaluate plan cost vs. self-hosting.
- A future feature needs server-side entitlement enforcement (e.g. shared/team
  content) → revisit the "gate is UX-only" stance.
- Any desire to drop the third-party SDK → migrate to StoreKit 2-only (the
  `pro` boolean abstraction is intended to make this swap cheap).

---

## Acceptance

- [ ] Human accepted before implementation (ratifies the monetization-only cloud
      dependency and its scope limits).
- [ ] OpenSpec change `add-tile-paywall` cites this ADR.
- [ ] ADR-0001 cross-referenced/amended for the no-cloud scope carve-out.
- [ ] TRD records RevenueCat SDK as a dependency.
- [ ] Architecture docs updated after implementation evidence exists.
