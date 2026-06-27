## ADDED Requirements

### Requirement: Pairing brute-force protection

The system SHALL limit wrong pairing-code attempts across the whole pairing
session (not per connection), and after a threshold SHALL lock out further
attempts for a cooldown and rotate the displayed code so prior guesses are
worthless. The attempt count SHALL reset only on a successful pair or an explicit
restart of advertising — never when a connection drops.

#### Scenario: Repeated wrong codes trigger lockout and rotation

- **WHEN** a peer submits the maximum allowed number of wrong codes (5),
  including across separate reconnecting sockets
- **THEN** the Mac rejects with reason `tooManyAttempts`, rotates to a new code
  shown in its UI, and drops the connection; further attempts are ignored until
  the cooldown (30 s) elapses

#### Scenario: Reconnecting per guess does not reset the limit

- **WHEN** a peer opens a new connection for each wrong-code attempt
- **THEN** the attempts still accumulate toward the same session limit and the
  lockout still triggers

#### Scenario: Lockout expires and a correct code then works

- **WHEN** the cooldown elapses after a lockout and the user enters the current
  (rotated) code
- **THEN** pairing succeeds and the attempt count is cleared

### Requirement: Typed rejection reasons

The system SHALL communicate why a pairing/reconnect attempt was rejected using a
typed reason so the remote can react distinctly.

#### Scenario: Remote distinguishes lockout from a wrong code

- **WHEN** the Mac rejects an attempt
- **THEN** it sends a typed reason — `incorrectCode`, `tooManyAttempts`, or
  `pairingExpired` — and the phone shows the corresponding message rather than a
  generic error

### Requirement: Session token stored securely

The system SHALL store the reconnect session token in the platform Keychain
(device-only, not iCloud-synced), not in plaintext UserDefaults, and SHALL
migrate any pre-existing plaintext token into the Keychain once.

#### Scenario: Token persists in the Keychain

- **WHEN** a phone pairs and later relaunches
- **THEN** the token used for silent reconnect is read from the Keychain, and no
  plaintext token copy remains in UserDefaults

### Requirement: Unauthenticated-connection reaping and connection limits

The system SHALL bound resources for inbound connections: it SHALL cap the number
of simultaneously-open connections and SHALL close any connection that does not
complete pairing or token reconnect within a short timeout.

#### Scenario: Idle unauthenticated socket is closed

- **WHEN** a peer connects but sends no valid `pair`/`reconnect` within the
  auth-timeout (15 s)
- **THEN** the Mac closes that connection

#### Scenario: Connections beyond the cap are refused

- **WHEN** more than the allowed number of inbound connections are opened at once
- **THEN** the excess connections are refused, and a slot frees once an existing
  connection closes
