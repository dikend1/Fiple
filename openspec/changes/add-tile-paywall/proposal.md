# Change: Add tile paywall (free tier + Fiple Pro)

## Why

Fiple needs a revenue model that does not compromise the core loop. Defining
tiles on the Mac stays free and unlimited (the Mac is the authoring surface and
the source of truth). Monetization happens on the phone, where the value is
realized: the **first 8 tiles are usable for free**, and unlocking the rest
requires **Fiple Pro**. This keeps the free experience genuinely useful while
giving power users — exactly the people who build large preset libraries — a
reason to pay. Pricing offers both a recurring and a one-time path so we capture
subscription-averse buyers and low-commitment buyers from one entitlement.

## What Changes

- Add a per-device entitlement (`pro`) consumed only by the **iOS** app. The Mac
  is unaffected — it keeps creating/editing/reordering tiles with no limit.
- Gate the iOS tile grid: the first 8 tiles (by the Mac's order) are runnable for
  free; tiles beyond index 8 render in a **locked** state and are not runnable
  until `pro` is active.
- Add a paywall presented when the user taps a locked tile (or from a "Get Pro"
  entry point), offering two products that both grant `pro`:
  - **Fiple Pro — Monthly** ($2.99, auto-renewing subscription)
  - **Fiple Pro — Lifetime** ($29.99, non-consumable one-time purchase; value pick)
- Integrate **RevenueCat** (over StoreKit 2) for purchase, entitlement
  resolution, and restore. No first-party receipt server.
- Add **Restore Purchases** and honest entitlement state (active / not active /
  unknown-offline) in the iOS UI.

## Impact

- Affected specs: `entitlement-gating` (new capability)
- Affected code: new — iOS purchase/entitlement layer + paywall UI + tile-grid
  gating; RevenueCat SDK added as the first third-party dependency (exact files
  unknown until scaffold). Mac targets untouched. Shared protocol untouched (the
  Mac still sends the full tile snapshot; gating is presentation-side on iOS).
- New external dependencies: **RevenueCat SDK**, **App Store / StoreKit 2**.
- **Blocked on:** a new ADR. ADR-0001 fixed a *no-cloud* topology for the
  remote-control data path. This change adds a cloud dependency (RevenueCat +
  App Store) for **monetization only** — the LAN control path stays cloud-free.
  That delta is material and must be ratified by an ADR (proposed
  `adr/0003-monetization-entitlement-dependency.md`) before implementation.
- Related design docs (to author/update before approval):
  - docs/design-docs/brd/fiple-mvp.md (add revenue model)
  - docs/design-docs/prd/ (new PRD: free tier + Pro paywall)
  - docs/design-docs/adr/0003-monetization-entitlement-dependency.md (new)
