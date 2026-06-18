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

## 6. Non-Goals

- AI voice commands (deferred to v1.1).
- Editing tiles from the phone (Mac is the only place tiles are managed).
- Window positioning / layout restoration.
- Apple Shortcuts integration, multi-step conditional scenarios.
- Cross-device or cross-network operation (cloud relay).
- Team / shared workspaces, productivity analytics.

---

## 7. Open Questions

| Question | Owner | Status |
| --- | --- | --- |
| Pricing / monetization model for MVP (free vs paid) | maksat | open |
| Distribution: Mac App Store vs direct (sandbox limits on `open -a`/Apple Events) | maksat | open |
| Minimum supported macOS / iOS versions | maksat | open |
