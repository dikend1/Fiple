# Design Docs — Agent Rules

This directory contains design inputs and target contracts. It is not current implemented architecture. Current implemented architecture lives in `docs/architecture/`.

## When To Write What

Use this decision tree before creating an OpenSpec change:

```text
Is there a business case or MVP scope to validate?
  Yes, but idea is under-researched -> use market-research skill, save consensus note
  Yes, enough context exists -> write a BRD in docs/design-docs/brd/
  No  -> continue

Is product behavior or UX unclear?
  Yes -> create a consensus note in docs/design-docs/consensus/
  No  -> write a PRD in docs/design-docs/prd/

Is technical implementation shape unclear?
  Yes -> write a TRD in docs/design-docs/trd/
  No  -> continue

Does this materially change architecture?
  Yes -> write an ADR in docs/design-docs/adr/ and get human acceptance
  No  -> continue

Proceed to OpenSpec change in openspec/changes/
```

## Flow

| Step | Document | Folder | Gate |
| --- | --- | --- | --- |
| 0 | Research / Consensus | `consensus/` | recommended when idea needs validation |
| 1 | BRD | `brd/` | human `accepted` before MVP implementation |
| 2 | Consensus | `consensus/` | optional, useful when behavior is unclear |
| 3 | PRD | `prd/` | required before product OpenSpec change |
| 4 | TRD | `trd/` | required when stack/data/modules are not obvious |
| 5 | ADR | `adr/` | human `accepted` before material architecture change |
| 6 | OpenSpec Change | `../../openspec/changes/` | approved before implementation |

## Gates

- `accepted` is human-only. Agents do not set it autonomously.
- Do not implement a new MVP feature without a BRD and PRD.
- Do not implement a material architecture decision without an accepted ADR.
- Do not use design docs as current architecture.
- Do not create an ExecPlan. Use OpenSpec change files instead.

## Templates

- `brd/_template.md`
- `prd/_template.md`
- `trd/_template.md`
- `adr/_template.md`

## Skills

- `market-research` — structured market, competitor, feasibility, cost, and risk research before BRD.
