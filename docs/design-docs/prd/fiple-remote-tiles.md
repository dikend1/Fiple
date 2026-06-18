# Fiple — Tiles, Workspaces & Remote Execution (PRD)

> type: prd
> status: draft
> date: 2026-06-18
> deciders: []
> relates-to: brd/fiple-mvp.md

---

## Overview

This PRD covers what the user can do with tiles: how they are managed on the Mac,
how they appear and are triggered on the phone, and what feedback the user gets
when actions run. It assumes a working pairing (see `prd/fiple-pairing.md`). The
core principle from the BRD: **the Mac is the source of truth and the only place
tiles are managed; the phone is purely a remote** that views and triggers.

---

## User-Observable Properties

- **Mac-only management** — Tiles are created, edited, reordered, and deleted in
  the Mac app. The phone has no editing forms or pickers.
- **Real app picking on Mac** — When building a tile, the Mac offers the list of
  actually installed applications (name + icon + bundle id), so the user picks a
  real app rather than typing a path.
- **Tile = 1+ actions** — A tile may hold a single action or several. Several
  actions in order make a workspace preset; there is no separate "workspace"
  object the user must learn.
- **Three action types** — `launchApp`, `openURL`, `openFile` (file or folder,
  opened in the default or a specified app).
- **Phone mirrors the Mac** — The phone shows the current tile grid received from
  the Mac. When tiles change on the Mac, the phone's grid updates automatically.
- **One-tap trigger** — Tapping a tile on the phone runs all of its actions on
  the Mac in order.
- **Per-action feedback** — After a trigger, the phone shows which actions
  succeeded and which failed. A failure in one action does not stop the others.

---

## Core Flow

1. On the Mac, the user creates a tile "Start Coding" and adds actions: launch
   Cursor, open `github.com/...`, launch Terminal, open the project folder.
2. The Mac stores the tile and pushes the updated tile list to the paired phone.
3. On the phone, the user sees "Start Coding" in the grid and taps it.
4. The phone sends `{ run: tileId }`; the Mac executes each action in order.
5. The Mac returns a per-action result; the phone shows a checkmark per action
   and highlights anything that failed (e.g., app not installed, file missing).

---

## Success Criteria

- [ ] A workspace preset of 4+ actions is created on the Mac and triggered from
  the phone in one tap.
- [ ] All actions in a triggered tile run; a single failing action does not abort
  the rest.
- [ ] The phone reflects tile changes made on the Mac without a manual refresh.
- [ ] The phone surfaces a clear per-action success/failure result after a
  trigger.
- [ ] The phone never lets the user edit tiles.

---

## Constraints

- The phone holds no authoritative tile data; it renders what the Mac sends.
- Action execution happens only on the Mac.
- A tile's actions execute in their defined order.

---

## Out Of Scope

- Editing/creating tiles from the phone.
- Conditional or branching multi-step scenarios.
- Window placement after launch.
- AI/voice-driven tile creation or triggering (v1.1).

---

## Open Questions

| Question | Owner | Status |
| --- | --- | --- |
| Should `openFile` allow specifying which app opens it, or default only, in MVP | maksat | open |
| Behavior when an action is slow/hangs (timeout + reporting) | maksat | open |
| Max number of actions per tile (if any) | maksat | open |
