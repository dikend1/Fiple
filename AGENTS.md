# Agent Guide

## First Reads

- Read `docs/architecture/index.md` before inferring runtime architecture; it is the implemented truth.
- Read the area `AGENTS.md` before touching `docs/design-docs/`, `docs/architecture/`, or `openspec/`.
- Treat `docs/design-docs/` as intent/target contracts, not implemented behavior. `accepted` status is human-only.
- OpenSpec active work is under `openspec/changes/`; current implemented specs are under `openspec/specs/`.

## Build And Test

- `Fiple.xcodeproj` is generated from `project.yml` by XcodeGen and is ignored. Run `xcodegen generate` after changing `project.yml` or after a fresh clone.
- Core tests: `cd FipleKit && swift test`.
- Focused package test: `cd FipleKit && swift test --filter TileRunnerTests` or another Swift Testing suite/test name.
- App builds: `xcodebuild -project Fiple.xcodeproj -scheme FipleMac -destination 'platform=macOS' build`.
- iOS build: `xcodebuild -project Fiple.xcodeproj -scheme FipleiOS -destination 'generic/platform=iOS Simulator' build`.
- `buildServer.json` is machine-specific SourceKit-LSP config and is ignored.

## Implemented Shape

- `FipleKit/` is the shared Swift package for pure/tested core: tile/action models, message and frame codecs, pairing code, tile runner, and Network.framework transport.
- `Apps/FipleMac/` is the Mac source of truth and executor: JSON tile persistence in Application Support, Bonjour advertising, pair/token handshake, snapshot push, and `NSWorkspace` action execution.
- `Apps/FipleiOS/` is remote-only: silent Bonjour discovery, code/token auth, tile snapshots, and run triggers. Do not add tile editing here unless the specs change.
- Transport is Bonjour `_fiple._tcp` plus `NWListener`/`NWConnection` with 4-byte big-endian length-prefixed JSON frames, not WebSocket.

## Workflow Constraints

- Keep changes scoped to one OpenSpec change; do not mix unrelated features.
- Do not create ExecPlans. Use OpenSpec `proposal.md`, `tasks.md`, optional `design.md`, and capability `spec.md` deltas.
- Every OpenSpec requirement needs at least one `#### Scenario:` using `WHEN` / `THEN`.
- Record verification evidence in the relevant OpenSpec `tasks.md` before marking implementation tasks done.
- After verified implementation, update `openspec/specs/`, archive the change, then update `docs/architecture/` from code/runtime evidence.

## Architecture Gates

- Material architecture changes need an accepted ADR before implementation. Material means changing module boundaries, communication, persistence contracts, public interfaces, or replacing an existing decision.
- Prefer the smallest native Swift solution; do not add backend, database, auth, analytics, payments, cloud, or third-party dependencies unless accepted docs/OpenSpec require it.
- Swift is strict-concurrency mode; preserve `@MainActor`, actors, and async boundaries rather than papering over isolation errors.
