## ADDED Requirements

### Requirement: Stale-file candidate detection

The Mac SHALL scan the user-granted folders daily and flag files whose
last-open date is older than the configured threshold (default 60 days) as
deletion candidates, each with a review deadline (7 days from candidacy).
Candidate files SHALL NOT be moved or altered while awaiting review.

#### Scenario: An old screenshot becomes a candidate

- **WHEN** the daily scan finds a file in a granted folder not opened for at
  least the threshold
- **THEN** the file is added to the candidate list with its size, thumbnail
  availability, and a deadline 7 days out — and remains untouched on disk

#### Scenario: A used file leaves the list

- **WHEN** a candidate file is opened, modified, moved, or deleted before its
  deadline
- **THEN** the next scan (and any pre-enforcement check) removes it from the
  candidate list without any action

### Requirement: Deadline enforcement into the system Trash only

The Mac SHALL move candidates that pass their deadline unreviewed to the system
macOS Trash, and SHALL NOT permanently delete any file. Deadlines missed while
the Mac was off or asleep SHALL be enforced at the next launch.

#### Scenario: Unreviewed candidate auto-trashes

- **WHEN** a candidate's deadline passes with no user decision
- **THEN** the Mac moves the file to the system Trash and posts a local
  notification summarizing what moved

#### Scenario: Missed deadline enforced on launch

- **WHEN** the Mac starts after being asleep past one or more deadlines
- **THEN** those candidates are re-validated (still stale, still present) and
  then moved to the system Trash

### Requirement: Phone review by id with keep-list

The phone SHALL present the synced candidate list for review and SHALL send
only candidate ids with a `keep` or `trash` decision; the Mac SHALL resolve ids
against its own store and act only on matches. `keep` SHALL permanently exclude
the file from future scans.

#### Scenario: Batch trash from the phone

- **WHEN** the user selects several candidates and confirms "Move to Trash"
- **THEN** the Mac moves each resolved file to the system Trash and pushes an
  updated candidate list

#### Scenario: Keep excludes forever

- **WHEN** the user marks a candidate "Keep"
- **THEN** it leaves the candidate list and is never proposed again, even if it
  stays unopened

#### Scenario: Unknown id is ignored

- **WHEN** an action arrives for an id not in the Mac's candidate store
- **THEN** the Mac performs no filesystem action for that id and reports it in
  the typed result

### Requirement: Thumbnails over the existing LAN channel

The Mac SHALL serve per-candidate thumbnails (QuickLook-generated JPEG) on
request over the existing paired LAN channel; the phone SHALL fetch them lazily
for visible items.

#### Scenario: Grid shows previews

- **WHEN** the phone displays candidate cells
- **THEN** it requests thumbnails for visible ids and renders them; items
  without a thumbnail show a document icon with name and size

### Requirement: Opt-in with user-granted folder access

Smart Trash SHALL be off by default. Enabling it SHALL require the user to
grant folder access through the system open panel; access persists via
security-scoped bookmarks. Disabling SHALL stop scanning and clear pending
candidates without touching any file.

#### Scenario: Enabling requests folder access

- **WHEN** the user turns Smart Trash on in the Mac settings
- **THEN** a folder picker is shown (Downloads and Desktop suggested), and only
  granted folders are ever scanned

#### Scenario: Disabling is non-destructive

- **WHEN** the user turns Smart Trash off
- **THEN** scanning stops and pending candidates are discarded; no file moves

### Requirement: Deadline reminders without a backend

The system SHALL remind the user before auto-trash using local notifications
only: on the Mac when items are within 2 days of deadline, and on the phone via
a local notification scheduled at each sync for 2 days before the nearest
deadline.

#### Scenario: Phone reminder scheduled at sync

- **WHEN** the phone syncs a candidate list containing future deadlines
- **THEN** it (re)schedules one local notification for the nearest deadline
  minus 2 days, replacing any previously scheduled reminder
