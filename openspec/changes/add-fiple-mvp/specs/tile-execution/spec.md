## ADDED Requirements

### Requirement: One-tap tile execution

The system SHALL execute all actions of a tile on the Mac, in order, when the
tile is tapped on the phone.

#### Scenario: Trigger a workspace preset

- **WHEN** the user taps a tile with multiple actions on the phone
- **THEN** the Mac runs each action in its defined order (launch apps, open URLs,
  open files)

### Requirement: Independent per-action results

The system SHALL execute each action independently and report a per-action
result; a single failed action SHALL NOT abort the remaining actions.

#### Scenario: One action fails

- **WHEN** a triggered tile includes an action that cannot complete (e.g., app
  not installed or file missing)
- **THEN** the remaining actions still run and the phone shows which actions
  succeeded and which failed

#### Scenario: Successful execution feedback

- **WHEN** all actions of a triggered tile complete successfully
- **THEN** the phone shows a success result for each action
