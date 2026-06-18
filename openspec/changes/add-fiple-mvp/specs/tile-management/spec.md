## ADDED Requirements

### Requirement: Mac-only tile management

The system SHALL allow creating, editing, reordering, and deleting tiles only on
the Mac. The phone SHALL NOT provide any tile editing.

#### Scenario: Create a workspace preset on the Mac

- **WHEN** the user creates a tile on the Mac and adds multiple actions
  (launch app, open URL, open file)
- **THEN** the tile is stored on the Mac as the source of truth with its ordered
  actions

#### Scenario: Pick from installed apps

- **WHEN** the user adds a `launchApp` action on the Mac
- **THEN** the Mac offers the list of actually installed applications
  (name, icon, bundle id) to choose from

#### Scenario: Phone cannot edit

- **WHEN** the user views tiles on the phone
- **THEN** no create/edit/delete/reorder controls are available on the phone

### Requirement: Tile snapshot mirroring

The system SHALL push the current tile list to the paired phone, and the phone
SHALL render it and update automatically when tiles change on the Mac.

#### Scenario: Tiles change on the Mac

- **WHEN** the user adds, edits, reorders, or deletes a tile on the Mac while a
  phone is connected
- **THEN** the phone's tile grid updates without a manual refresh
