# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A **spec-driven MVP workspace** that has now reached a first implementation
slice. It uses the *agentic-development-skills* framework to take a product idea
from business case → executable requirements → code. Design documents live in
`docs/design-docs/` and `openspec/`; the code lives in `FipleKit/` and `Apps/`.

## Build, test, run

The Xcode project is **generated** from `project.yml` via XcodeGen and is not
committed — regenerate it after pulling or changing `project.yml`:

```bash
xcodegen generate                                   # → Fiple.xcodeproj
cd FipleKit && swift test                            # core unit + loopback tests
xcodebuild -project Fiple.xcodeproj -scheme FipleMac -destination 'platform=macOS' build
xcodebuild -project Fiple.xcodeproj -scheme FipleiOS -destination 'generic/platform=iOS Simulator' build
```

Toolchain: Swift 6.3 / Xcode 26, Swift 6 language mode with complete strict
concurrency. No third-party dependencies.

The MVP being planned is **Fiple**: an iPhone app that acts as a remote control
for a Mac. The user defines "Tiles" on the Mac (each launches one or more
actions: open an app, URL, or file); a tile with several actions is a workspace
preset. Tapping a tile on the phone restores a working context on the Mac. See
`docs/design-docs/brd/fiple-mvp.md` for the full business case.

## Authoritative governance — read before acting

The operating rules live in `AGENTS.md` files and override default behavior.
Read the relevant one before working in that area:

- `openspec/project.md` — project context, stack-selection policy, conventions.
- `docs/design-docs/AGENTS.md` — when to write BRD / PRD / TRD / ADR; the gate table.
- `openspec/AGENTS.md` — how to author and execute OpenSpec changes.
- `docs/architecture/AGENTS.md` — architecture docs are implemented truth only.

## The document flow (and where authority lives)

Work moves through this pipeline; each stage cites the one before it:

```
BRD → (Consensus) → PRD → TRD → (ADR) → OpenSpec change → implementation
```

| Surface | Meaning |
| --- | --- |
| `docs/design-docs/` | **Intent / target contracts** (BRD, PRD, TRD, ADR). NOT current architecture. |
| `docs/architecture/` | **Implemented truth only.** Update from code evidence *after* a change ships — never speculative. |
| `openspec/specs/` | **Current implemented capabilities.** Empty until a change is implemented and archived. |
| `openspec/changes/<id>/` | **Active work**: `proposal.md`, `tasks.md`, `design.md`, `specs/<capability>/spec.md`. Replaces ExecPlans. |

## Hard rules (these block work)

- **`accepted` / `revised → accepted` is human-only.** Agents never set acceptance
  status autonomously. All current Fiple docs are `draft`.
- **No MVP implementation without an accepted BRD and PRD.** No material
  architecture change without an accepted ADR (see the ADR materiality list in
  `docs/architecture/AGENTS.md`).
- **Every OpenSpec requirement needs ≥1 `#### Scenario:`** written as `WHEN` / `THEN`.
- **Spec deltas use `## ADDED|MODIFIED|REMOVED|RENAMED Requirements`** headers.
- Keep changes scoped to one OpenSpec change; don't mix unrelated features.
- Prefer OpenSpec deltas over chat-only instructions.

## Authoring an OpenSpec change

1. Pick a unique verb-led id (`add-`, `update-`, `remove-`, `refactor-`).
2. Scaffold `proposal.md`, `tasks.md`, `design.md` (when technical decisions
   exist), and `specs/<capability>/spec.md`.
3. Validate (when the CLI is installed): `openspec validate <change-id> --strict`.
4. Implement only after human approval, completing `tasks.md` sequentially and
   recording verification evidence in `tasks.md` before marking a task done.
5. After verification: update `openspec/specs/`, move the change to
   `openspec/changes/archive/YYYY-MM-DD-<id>/`, and update `docs/architecture/`.

## Current state

- Active change: `openspec/changes/add-fiple-mvp/` (capabilities: `pairing`,
  `tile-management`, `tile-execution`). **Not yet approved or implemented.**
- All design docs are `draft`; open questions are tracked in each doc.
- **Planned stack (per draft TRD `docs/design-docs/trd/fiple-mvp.md`):** two
  native SwiftUI apps (macOS menu-bar companion + iOS remote) talking over the
  LAN via Bonjour discovery + WebSocket with a JSON message protocol. No cloud,
  no account, no backend. This is not final until the TRD/ADR are accepted.

## Stack-selection policy (when code begins)

Prefer the smallest stack that demonstrates the MVP. Avoid backend, database,
auth, payments, deployment, analytics, and external AI APIs unless the PRD/TRD
requires them. Record any external dependency in the TRD or OpenSpec `design.md`
before adding it.
