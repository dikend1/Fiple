## ADDED Requirements

### Requirement: Curated Fiple Bar of quick actions

The Mac SHALL maintain a curated "Fiple Bar" of single quick actions (apps,
websites, shortcuts) and SHALL sync it to a paired remote, which SHALL render the
bar and trigger its actions by id. The bar is part of the Mac's authoritative
state and persists across launches.

#### Scenario: Fiple Bar syncs on connect

- **WHEN** a remote pairs or reconnects
- **THEN** the Mac sends the current Fiple Bar (`fipleBar`) alongside the tiles
  snapshot, and the remote renders it

#### Scenario: Bar updates propagate

- **WHEN** the user changes the Fiple Bar on the Mac while a remote is connected
- **THEN** the Mac pushes the updated bar and the remote reflects the change

#### Scenario: Tapping a bar action runs it on the Mac

- **WHEN** the user taps a Fiple Bar item on the remote
- **THEN** the remote sends the action's id, and the Mac resolves and runs that
  saved action (subject to server-authoritative execution and the URL allowlist)
