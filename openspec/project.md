# Project Context

## Purpose

This workspace is for building an MVP through spec-driven development with coding agents.

## Tech Stack

Unknown until the first MVP TRD/OpenSpec change selects it.

When selecting a stack:

- prefer the smallest stack that can demonstrate the MVP;
- avoid backend, database, auth, payments, deployment, analytics, and external AI APIs unless required by the PRD/TRD;
- record the decision in TRD or ADR before implementation.

## Project Conventions

### Documentation

- Design intent lives in `docs/design-docs/`.
- Current implemented architecture lives in `docs/architecture/`.
- Current product/system requirements live in `openspec/specs/`.
- Active implementation work lives in `openspec/changes/`.

### Code Style

- Follow the stack selected by the accepted TRD/OpenSpec change.
- Use existing conventions once code exists.
- Keep implementation slices small and reversible.

### Architecture Patterns

- Do not introduce material architecture without an accepted ADR.
- Keep v1 architecture boring and explicit.
- Prefer one typed contract over parallel old/new paths.

### Testing Strategy

- Every OpenSpec requirement needs at least one scenario.
- Every implementation task needs verification evidence.
- UI work needs browser/manual acceptance evidence.
- Logic-heavy work needs tests when practical.

### Git Workflow

- Keep changes scoped to the active OpenSpec change.
- Do not mix unrelated features in one change.

## Domain Context

The specific startup idea is not fixed in this template. The first BRD defines the target user, problem, and MVP scope.

## Important Constraints

- This is an MVP workspace for students/founders.
- Optimize for agent reliability and plan-following.
- Avoid broad, production-grade scope unless explicitly required.
- Prefer OpenSpec deltas over chat-only instructions.

## External Dependencies

None by default.

Any external dependency must be justified in TRD/OpenSpec `design.md`.
