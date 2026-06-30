# Fiple — Free Tier & Fiple Pro Paywall (PRD)

> type: prd
> status: draft
> date: 2026-06-30
> deciders: []
> relates-to: brd/fiple-mvp.md

---

## Overview

This PRD covers Fiple's revenue model from the user's perspective: what is free,
what costs money, and how the user buys and restores **Fiple Pro**. It builds on
`prd/fiple-remote-tiles.md` (tiles are authored on the Mac, run from the phone)
and `prd/fiple-pairing.md`. Principle: **authoring on the Mac is always free and
unlimited; the paywall lives on the phone**, where value is realized. The first 8
tiles run free; unlocking the rest requires Pro. Implementation and the cloud
dependency are covered by ADR-0003 and OpenSpec change `add-tile-paywall`.

---

## User-Observable Properties

- **Free Mac authoring** — Creating, editing, reordering, and deleting tiles on
  the Mac is always free and has no limit, regardless of Pro status.
- **Generous free quotas on the phone** — Without Pro, the first **8 Fiple Bar
  apps** (quick-launch grid) and the first **2 Workspaces** (presets) are fully
  runnable, identical to the Pro experience. Each surface counts independently in
  the Mac's order.
- **Visible locked items** — Items beyond a surface's free quota appear greyed
  with a lock rather than hidden, so the user sees what Pro unlocks.
- **Tap-to-unlock** — Tapping a locked item opens the paywall instead of running.
- **Three ways to buy** — **Fiple Pro Monthly** ($2.99) and **Yearly** ($14.99)
  auto-renewing subscriptions, and **Fiple Pro Lifetime** ($39.99) one-time. Any
  of them unlocks everything; the user never has to understand "entitlements,"
  only "I have Pro." Yearly is framed as the value pick (saves ~58% vs paying
  monthly).
- **Instant unlock** — A successful purchase unlocks all tiles immediately, no
  app restart.
- **Restore** — A Restore Purchases control regains Pro on a new device or after
  reinstall.
- **Honest offline** — A user who already has Pro stays unlocked offline; the app
  never revokes Pro because the store is temporarily unreachable.

---

## Core Flow

1. A free user has 10 quick-launch apps in the Fiple Bar; the phone runs the
   first 8 normally and shows the last 2 greyed with a lock. Likewise only the
   first 2 of their workspaces run.
2. The user taps a locked item. The paywall appears with three options — Monthly,
   Yearly, and Lifetime — each showing its localized price (subscriptions show
   their renewal period; Yearly is highlighted as the best value).
3. The user buys Yearly. The purchase completes; all 11 tiles become runnable
   immediately.
4. Later the user reinstalls on a new phone, opens Fiple, and taps Restore
   Purchases; Pro is restored and all tiles unlock.
5. A user who bought Lifetime opens the app on a plane with no signal; their tiles
   are unlocked from cached entitlement.

---

## Success Criteria

- [ ] A free user can run the first 8 Fiple Bar apps and first 2 workspaces with
  no prompt and no degradation.
- [ ] Items beyond a surface's quota are visibly locked and tapping one opens the
  paywall.
- [ ] Buying Yearly or Lifetime unlocks all tiles without an app restart.
- [ ] Restore Purchases regains Pro on a fresh install.
- [ ] An existing Pro user is never locked out while offline.
- [ ] Mac tile authoring is never gated or limited.

---

## Constraints

- The paywall and gate exist only on the phone; the Mac has no monetization UI.
- Entitlement check is client-side (UX gate, not a security boundary) — see
  ADR-0003.
- Both products grant the same Pro access; the app must not branch behavior on
  which product was purchased.
- App Store rules: show Terms & Privacy, a Restore control, and clear renewal
  terms for the subscription.

---

## Out Of Scope

- Per-feature or tiered Pro (single all-or-nothing `pro`).
- Team/shared/family entitlements.
- Android or web purchases.
- Paywalling pairing, execution, or any Mac-side capability.

---

## Open Questions

| Question | Owner | Status |
| --- | --- | --- |
| Prices: Monthly $2.99 / Yearly $14.99 / Lifetime $39.99 | maksat | decided |
| Free quotas — Fiple Bar 8 / Workspaces 2 (tunable constants) | maksat | decided |
| Per-surface quotas vs one combined "N total" pool | maksat | open |
| Free trial / intro offer on Yearly | maksat | open |
| Paywall copy / value props shown | maksat | open |
| Should locked tiles be hidden instead of greyed (A/B later?) | maksat | open |
