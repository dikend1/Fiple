# OpenSpec Change Template

Use this as a copy reference. Do not keep template content inside an active change.

## proposal.md

```markdown
# Change: [Brief description]

## Why

[Problem/opportunity, tied to BRD/PRD.]

## What Changes

- [Change]
- [Change]

## Impact

- Affected specs: [capability names]
- Affected code: [expected files/modules, or unknown until scaffold]
- Related design docs:
  - docs/design-docs/brd/[file].md
  - docs/design-docs/prd/[file].md
  - docs/design-docs/trd/[file].md
```

## tasks.md

```markdown
## 1. Implementation

- [ ] 1.1 Inspect current repo and confirm stack.
- [ ] 1.2 Implement the smallest user-visible slice.
- [ ] 1.3 Add or update tests/checks.
- [ ] 1.4 Run verification and record evidence below.

## 2. Verification Evidence

| Check | Command / Method | Result |
| --- | --- | --- |
| Pending | Pending | Pending |
```

## specs/<capability>/spec.md

```markdown
## ADDED Requirements

### Requirement: [Capability]

The system SHALL [specific behavior].

#### Scenario: [happy path]

- **WHEN** [action/event]
- **THEN** [expected result]
```
