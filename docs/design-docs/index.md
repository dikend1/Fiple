# Design Docs

> Status: design-doc index

Design docs are idea, design, and target-contract surfaces. They are not current implemented architecture.

## Document Types

| Type | Folder | Lifecycle | Superseded when |
| --- | --- | --- | --- |
| BRD | `brd/` | draft -> accepted -> superseded | business goal changes or is cancelled |
| PRD | `prd/` | draft -> accepted -> revised -> superseded | product behavior changes materially |
| TRD | `trd/` | draft -> accepted -> revised -> superseded | implementation strategy changes materially |
| ADR | `adr/` | draft -> accepted -> superseded | architecture decision is replaced |
| Consensus | `consensus/` | permanent | never |
| Assets | `assets/` | reference | when no longer useful |
| Old | `old/` | archive | not active authority |

## Current Documents

> None accepted yet — all drafts pending human `accepted`.

| Type | Document | Status |
| --- | --- | --- |
| BRD | `brd/fiple-mvp.md` | draft |
| PRD | `prd/fiple-pairing.md` | draft |
| PRD | `prd/fiple-remote-tiles.md` | draft |
| TRD | `trd/fiple-mvp.md` | draft |
| ADR | `adr/0001-local-network-topology.md` | draft |

Implementing OpenSpec change: `openspec/changes/add-fiple-mvp/`.

## Consensus / Research

Use the repo-local `market-research` skill before BRD when the idea needs validation, competitor context, or technical feasibility review.

Research notes live in `consensus/` and should be cited by later BRDs/PRDs.

## Contract

- Every BRD/PRD/TRD/ADR file must include `status:` in frontmatter.
- `accepted` and `revised -> accepted` transitions are human-only.
- Superseded documents should link to their replacement.
- OpenSpec changes should cite the design docs they implement.
- After implementation, update `docs/architecture/` from code/runtime evidence.
