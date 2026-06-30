# Design: Add tile paywall (free tier + Fiple Pro)

This note records the implementation-shaping decisions. Product rationale lives
in the BRD/PRD; the cloud-dependency trade-off is ratified by the new ADR-0003.

## Where the gate lives

The gate is **iOS-presentation-side only**. The Mac remains authoritative and
unaware of entitlement: it sends the full `tilesSnapshot` as today. The phone
renders the whole list but marks tiles at index ≥ 8 (zero-based) as locked when
`pro` is inactive. Rationale:

- Keeps the wire protocol and the Mac targets unchanged (no breaking change).
- The Mac is the authoring surface; limiting authoring would hurt the product.
- Consistent with the server-authoritative model: locking is a client UX choice,
  not a security control. A bypass only unlocks tiles the user already owns on
  their own Mac — there is no shared/secret content to protect, so client-side
  enforcement is acceptable (same reasoning as the LAN threat model in ADR-0002).

## What the "8 tiles" limit counts (grounded in the real iOS UI)

The iOS Home renders two independent streams, not one flat grid:

- **Workspaces** — `RemoteController.workspaces` = `tiles.filter(\.isWorkspace)`
  (tiles with > 1 action). Rendered as the horizontal preset cards in
  `HomeView.workspaces` → `WorkspaceCardView`. This is the headline value.
- **Fiple Bar** — `RemoteController.fipleBar: [Action]`, a *separate* Mac-curated
  action list streamed via `ServerMessage.fipleBar`, rendered as the 4-col grid
  in `HomeView.quickAccess` → `QuickAccessTile`. Not derived from `tiles`.

**Decision (revised after user review 2026-06-30):** gate **both** surfaces, with
**different** free quotas — Fiple Bar **8** free (the lightweight hook that
accumulates many apps), Workspaces **2** free (the premium presets). A generic
`FreeTierGate.lockedIDs(_:freeLimit:isPro:)` over any `Identifiable` list drives
both — `lockedFipleBarActionIDs` (limit `freeFipleBarLimit = 8`) and
`lockedWorkspaceIDs` (limit `freeWorkspaceLimit = 2`) in `RemoteController`.

> Each surface caps independently, so a free user gets up to 8 free apps **and**
> 8 free workspaces. If product later wants a single combined "8 total" pool,
> that is a change in how the two derivations are computed; the UI/purchase
> layers are unaffected. A DEBUG free-limit override (Settings → Debug) lets QA
> see locks without 9+ real items.

## Implementation map (real files — for execution, no code written yet)

| Concern | File | Insertion |
| --- | --- | --- |
| Entitlement source | new `Apps/FipleiOS/EntitlementStore.swift` | `@Observable @MainActor`; configures RevenueCat; exposes `proState: .active/.inactive/.unknown` from cached + live `CustomerInfo` |
| Free/locked set | `Apps/FipleiOS/RemoteController.swift` | add `freeWorkspaceLimit = 8` and a derived `lockedWorkspaceIDs: Set<UUID>` (positions ≥ limit in `workspaces`); pure, testable |
| Block locked runs | `RemoteController.run(_:)` (line ~191) | if `lockedWorkspaceIDs.contains(tile.id)` and not Pro → don't send `run`; signal "show paywall" instead |
| Locked card UX | `Apps/FipleiOS/Views/Home/WorkspaceCardView.swift` + `HomeView.workspaces` (line ~78) | grey + lock badge when locked; tap routes to paywall, not `controller.run` |
| Paywall | new `Apps/FipleiOS/Views/Paywall/PaywallView.swift` | three RevenueCat packages, prices, Restore, Terms/Privacy; presented as a sheet |
| "Get Pro" entry | `Apps/FipleiOS/Views/Settings/SettingsView.swift` + `HomeView` header | always-available entry to the paywall |
| SDK | `project.yml` `FipleiOS.dependencies` | add `package: RevenueCat` (+ a `packages:` SPM entry); first third-party dep |

Gate logic lives in `RemoteController` (already `@MainActor @Observable`, holds
`tiles`); `EntitlementStore` is injected so the controller can ask "is Pro?".
The wire protocol, `FipleKit`, and the Mac targets are untouched.

## Free-tier semantics

- **Which 8 are free:** the first 8 tiles in the Mac's canonical order (the same
  order shown on the Mac). Deterministic, needs no extra state, and reordering on
  the Mac changes which tiles are free — predictable to the user.
- **Locked tile UX:** locked tiles stay **visible** (greyed + lock badge) rather
  than hidden — visibility is the conversion driver. Tapping a locked tile opens
  the paywall instead of running it.
- **Boundary cases:** ≤ 8 tiles → nothing is ever locked, paywall only reachable
  from the explicit "Get Pro" entry. Crossing 8 (Mac adds a 9th) → the 9th
  appears locked live in the existing snapshot flow.
- **Lapse:** when a subscription expires and is not Lifetime, tiles ≥ 8 re-lock
  on the next entitlement refresh.

## Products → one entitlement

| Product (App Store Connect id) | Type | Price | Grants |
| --- | --- | --- | --- |
| `pro_monthly` | Auto-renewing subscription | $2.99 | entitlement `pro` |
| `pro_yearly` | Auto-renewing subscription | $14.99 | entitlement `pro` |
| `pro_lifetime` | Non-consumable | $39.99 | entitlement `pro` |

All three map to RevenueCat entitlement `pro`. Code never branches on *which*
product unlocked — it asks only "is `pro` active?". Monthly and Yearly share one
subscription group. Prices anchor each other: Yearly ($14.99) saves ~58% vs
Monthly run-rate ($2.99 × 12 = $35.88); Lifetime ($39.99) ≈ 2.7× Yearly. Prices
are USD base tiers; the App Store localizes per region automatically.

## RevenueCat over StoreKit 2

- StoreKit 2 is the underlying payment rail (mandatory, Apple). RevenueCat wraps
  it: we call RevenueCat APIs, not StoreKit directly.
- RevenueCat is the receipt-validation backend so we write no server.
- Entitlement is read from `CustomerInfo.entitlements["pro"].isActive`.

## Entitlement state model (honest, offline-aware)

Three states drive the UI — never silently treat unknown as locked-forever:

| State | Meaning | Tile-grid behavior |
| --- | --- | --- |
| `active` | `pro` entitlement active | all tiles runnable |
| `inactive` | resolved, no `pro` | tiles ≥ 8 locked |
| `unknown` | not yet fetched / offline at launch | use last **cached** entitlement; do not downgrade a known-Pro user to locked on a transient network failure |

RevenueCat caches `CustomerInfo` on device, so a Pro user stays unlocked offline.

## Required UI surfaces

- **Paywall:** two products, prices localized via RevenueCat Offerings, "Restore
  Purchases", links to Terms & Privacy (App Store requirement for subscriptions).
- **Restore:** explicit control; re-syncs entitlement.
- **Manage:** for the subscription, a link to the system subscription management.

## Open questions (resolve before/at implementation)

- Free-tile count final (assume 8 unless the PRD revises it) — keep it a single
  named constant so it is tunable.
- Free trial / introductory offer on Monthly/Yearly (RevenueCat supports; product
  call).
