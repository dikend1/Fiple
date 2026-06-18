## ADDED Requirements

### Requirement: Code-based local pairing

The system SHALL pair one iPhone with one Mac on the same Wi-Fi using a 4-digit
code shown on the Mac, with no account, no cloud, and no list of nearby devices.

#### Scenario: Successful first-time pairing

- **WHEN** the user enters the Mac's displayed 4-digit code on the phone while
  both devices are on the same Wi-Fi
- **THEN** the phone discovers the Mac silently, the handshake succeeds, both
  devices show "connected", and the pairing is persisted on the phone

#### Scenario: Wrong or expired code

- **WHEN** the user enters an incorrect or expired code
- **THEN** the system rejects the attempt with a clear message and the Mac can
  generate a new code

### Requirement: Automatic reconnection

The system SHALL reconnect a previously paired phone to its Mac without
re-entering the code, until the user explicitly disconnects.

#### Scenario: Reconnect on next launch

- **WHEN** a previously paired phone launches on the same Wi-Fi as its Mac
- **THEN** it reconnects automatically with zero taps

#### Scenario: Explicit disconnect requires a new code

- **WHEN** the user disconnects from either device and later tries to reconnect
- **THEN** reconnection requires a newly generated code from the Mac

### Requirement: Honest connection state

The system SHALL always reflect whether the phone is connected and SHALL NOT
queue triggers against a dead link.

#### Scenario: Wi-Fi drops

- **WHEN** the devices lose the shared network
- **THEN** the phone shows "not connected" and does not silently send triggers
