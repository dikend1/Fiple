# OpenSpec Instructions

Use OpenSpec for active MVP changes. OpenSpec replaces ExecPlans in this workspace.

## Quick Checklist

- Read `openspec/project.md`.
- Check active changes in `openspec/changes/`.
- Check current specs in `openspec/specs/`.
- Pick a unique verb-led `change-id`: `add-`, `update-`, `remove-`, `refactor-`.
- Scaffold:
  - `proposal.md`
  - `tasks.md`
  - `design.md` when technical decisions are needed
  - `specs/<capability>/spec.md`
- Write spec deltas with `## ADDED|MODIFIED|REMOVED|RENAMED Requirements`.
- Every requirement must include at least one `#### Scenario:`.
- Validate with `openspec validate <change-id> --strict` when CLI is available.
- Do not implement until human approval.

## Relationship To Design Docs

- BRD explains why the capability matters.
- PRD explains user-visible behavior.
- TRD explains implementation shape when needed.
- ADR records material architecture decisions.
- OpenSpec change turns those documents into executable requirements and tasks.

## Change Structure

```text
openspec/changes/<change-id>/
├── proposal.md
├── tasks.md
├── design.md
└── specs/
    └── <capability>/
        └── spec.md
```

`design.md` is optional only when the technical path is obvious. For MVP work with new stack/data/API decisions, include it.

## Implementation Rule

During implementation, work from:

1. `proposal.md`
2. `design.md`
3. `tasks.md`
4. `specs/<capability>/spec.md`

Complete tasks sequentially. Record verification evidence in `tasks.md` before marking tasks done.

## Archiving Rule

After implementation and verification:

1. Update current specs in `openspec/specs/`.
2. Move the change to `openspec/changes/archive/YYYY-MM-DD-<change-id>/`.
3. Update `docs/architecture/` from implementation evidence.
4. Run `openspec validate --strict` when CLI is available.
