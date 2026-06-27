## ADDED Requirements

### Requirement: Server-authoritative action execution

The Mac SHALL NOT execute an action payload supplied by the remote. The remote
SHALL trigger actions by id only; the Mac SHALL resolve each id against its own
saved tiles and Fiple Bar and execute only an action that exists there. An id
that does not match a saved action SHALL be rejected.

#### Scenario: Trigger by id runs the saved action

- **WHEN** the remote sends `runAction(actionID:)` for an action present in the
  Mac's Fiple Bar or tiles
- **THEN** the Mac runs that saved action and returns its result

#### Scenario: Unknown or forged id is rejected

- **WHEN** the remote sends an `actionID` (or a crafted action) that the Mac
  never saved — e.g. an attempt to launch an app or shortcut not in the Mac's
  Fiple Bar / tiles
- **THEN** the Mac does not execute anything and returns a failure result so the
  remote can clear its pending state

### Requirement: URL scheme allowlist for openURL actions

The Mac SHALL open only `http`/`https` URLs from `openURL` actions and SHALL
reject other schemes.

#### Scenario: Dangerous scheme is blocked

- **WHEN** an `openURL` action resolves to a `file://`, custom, or non-web scheme
- **THEN** the Mac refuses to open it and reports a failure, rather than handing
  it to the system opener
