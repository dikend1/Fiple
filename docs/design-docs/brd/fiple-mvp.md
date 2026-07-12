# Fiple MVP — Business Requirements Document

> type: brd
> status: draft
> date: 2026-06-18
> deciders: []

---

## 1. Problem Statement

Knowledge workers — developers, designers, students, founders — work across many
tools at once. A developer constantly switches between Cursor, ChatGPT, GitHub,
Terminal, documentation, and the browser. After every interruption they must
reopen the right apps, hunt for tabs, and rebuild their working context by hand.

The real failure mode is **lost context, not lost apps**. Each rebuild costs
minutes and breaks concentration; across a day it adds up to significant lost
focus time. Existing launchers (Spotlight, Dock, Raycast, Alfred) make it fast to
*open one app*, but none of them restore a *working state* in one move. The cost
of not solving this is chronic context-switching friction and shallow work.

---

## 2. What Is Fiple

Fiple turns an iPhone into a **remote control for a Mac**. The user defines
**Tiles** on the Mac; a tile launches one or more actions (open an app, open a
URL, open a file/folder). A tile with several actions is a workspace preset
("Start Coding", "Deep Work", "Ship Update"). One tap on the phone restores the
whole working environment on the Mac.

Fiple **is not** a launcher that runs on the Mac itself, a window manager, or a
cloud productivity suite. It is a phone-as-remote layer whose single purpose is
**fast context restoration**: one tap to get back into flow after any
interruption.

---

## 3. Key Primitives

| Primitive | Description |
| --- | --- |
| **Tile** | A named, ordered, user-defined unit that holds 1+ actions. Invariant: a tile always belongs to exactly one Mac and is editable only on that Mac. |
| **Action** | A single executable step: `launchApp`, `openURL`, or `openFile`. Invariant: each action is independently executable and independently reports success/failure. |
| **Workspace preset** | A tile with multiple actions executed in order. Invariant: it is not a separate entity — just a tile with >1 action. |
| **Pairing** | A one-time, code-based trust link between one iPhone and one Mac over the local network. Invariant: a paired phone reconnects without re-entering the code until the user disconnects. |

---

## 4. Why Now

- AI coding tools (Cursor, ChatGPT, Copilot) multiplied the number of apps a
  single task spans, making context rebuilding worse than before.
- Apple's local-networking and SwiftUI stacks make a no-cloud, no-account
  iPhone↔Mac remote shippable by a small team.
- Launchers solved "open one thing fast" years ago but left "restore my whole
  working state" unsolved — an open gap to own.

---

## 5. Success Criteria

- [ ] A user can pair an iPhone and a Mac on the same Wi-Fi by entering a 4-digit
  code, with no account and no cloud, in under 30 seconds.
- [ ] After pairing once, the phone reconnects automatically on next launch.
- [ ] A user can create a workspace preset on the Mac and trigger it from the
  phone with one tap.
- [ ] Triggering a preset launches all of its actions, and the phone shows
  per-action success/failure.
- [ ] A user reports they can return to a working state in one tap instead of
  manually reopening each tool.

---

## 6. Revenue Model

Fiple is **free to try, paid to scale**. Authoring tiles on the Mac is always
free and unlimited — the Mac is where the work happens and where the product
proves its value. Monetization lives on the **phone**, gated on how many tiles
the user actually runs remotely:

- **Free tier** — the phone runs the first **8 Fiple Bar apps** (quick-launch
  grid) and the first **2 workspaces** (presets) free, identical to paid. Enough
  to prove the core "one tap back to flow" loop; heavy users — many apps, several
  presets — are the ones who convert.
- **Fiple Pro** — unlocks **unlimited** tiles on the phone. One entitlement,
  three ways to buy:

  | Product | Price | Type |
  | --- | --- | --- |
  | Monthly | $2.99 | auto-renewing subscription |
  | Lifetime | $29.99 | one-time purchase (value pick — pay once) |

**Rationale.** The people who build large preset libraries are exactly the power
users willing to pay; the free tier stays genuinely useful (not crippled) so the
funnel is "loved it → outgrew the free tier," not "hit a wall on day one." Monthly
matches the prevailing price point for comparable utilities; Lifetime gives the
subscription-averse a one-time path and anchors the deal. Prices are USD base
tiers; the App Store localizes per region.

**Dependency note.** Charging requires the App Store (StoreKit 2) and uses
**RevenueCat** for entitlement/restore — a monetization-only cloud dependency
that does **not** touch the no-cloud LAN control path. This is a deliberate,
scoped exception to the no-cloud posture, ratified by
`adr/0003-monetization-entitlement-dependency.md`. Product behavior is specified
in `prd/fiple-paywall.md` and delivered by OpenSpec change `add-tile-paywall`.

---

## 7. Non-Goals

- AI voice commands (deferred to v1.1).
- Editing tiles from the phone (Mac is the only place tiles are managed).
- Window positioning / layout restoration.
- Apple Shortcuts integration, multi-step conditional scenarios.
- Cross-device or cross-network operation (cloud relay).
- Team / shared workspaces, productivity analytics.

---

## 8. Open Questions

| Question | Owner | Status |
| --- | --- | --- |
| Pricing / monetization model — free 8 tiles + Pro (see §6) | maksat | decided |
| Distribution: Mac App Store vs direct (sandbox limits on `open -a`/Apple Events) | maksat | open |
| Minimum supported macOS / iOS versions | maksat | open |
