# Architecture — Agent Rules

`docs/architecture/` contains current implemented architecture only.

Do not write speculative future-state architecture here. Future intent belongs in:

- `docs/design-docs/trd/`
- `docs/design-docs/adr/`
- `openspec/changes/<change-id>/design.md`

## ADR Gate

Every material architecture change requires an ADR before implementation.

A change is material if it:

- introduces or removes a layer, package, or module boundary;
- changes how components communicate;
- changes a persistence contract;
- changes a public interface consumed by other layers or agents;
- replaces or retires an existing architectural decision.

## Update Rule

After an OpenSpec change is implemented and verified, update architecture docs from evidence:

- exact files/modules;
- runtime behavior;
- public interfaces;
- commands used to verify.

OpenSpec changes own execution. Architecture docs own implemented truth.
