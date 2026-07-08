# Terminal Multi-Session — Design

Date: 2026-07-08 · Status: approved in chat · Branch: `feat/remote-terminal`

## Goal

Run several independent shells on the Mac from one phone terminal screen —
e.g. three Claude Code chats in parallel — switching between them from a
session menu in the terminal's top bar.

## What already exists (no changes needed)

- `TerminalSessionRegistry` keeps any number of `ShellSession`s alive by id;
  each TLS connection is its own `ConnectionSession`; reattach-by-id with
  scrollback replay already works (`resumeSessionID`).
- The phone's `TerminalSession` class owns one connection + one SwiftTerm
  buffer, with background/resume handling.

## Changes

### FipleKit (wire)

- New `TerminalClientControl.endSession(sessionID:)` — the phone explicitly
  closes a tab; the Mac kills that shell immediately instead of waiting for
  the reattach grace period. An older Mac skips the unknown control type and
  the shell dies at grace expiry — soft degradation. Codec round-trip test.

### Mac

- `TerminalService` handles `endSession`: terminate the pty via the registry
  (only for sessions owned by this authenticated connection's token).

### iOS

- `TerminalMultiSession` (@MainActor @Observable): ordered list of up to
  **5** tabs, each wrapping an existing `TerminalSession` with an
  auto-assigned name ("Session 1", "Session 2", …). All tabs stay connected
  in parallel; each keeps its own buffer, so switching shows everything that
  arrived while backgrounded.
- `TerminalScreen` hosts the active tab's terminal view. The top-bar title
  becomes a **session menu**:
  - one row per session: activity dot, name, ✓ on the current one;
  - the dot marks **unseen output** — it lights up when a background session
    produced output since it was last viewed (the "which Claude finished?"
    signal); the connected/disconnected state colors it green/gray;
  - "New Session" (disabled at the 5-tab cap) and "Close Session" at the
    bottom; closing sends `endSession` and drops the tab (last tab closes the
    screen);
  - the menu button shows the session count when more than one is open.
- The master password entered on opening the screen is reused to
  authenticate each new tab automatically.

## Out of scope (deliberate)

Renaming sessions, reordering, Safari-style tab previews, per-session
persistence across screen dismissal beyond the existing grace-period resume.

## Testing

- FipleKit: `endSession` codec round-trip; registry kill-by-id unit test.
- Existing loopback tests keep covering auth/resume.
- Manual: two+ tabs with `top` running in one while typing in another;
  unseen-output dot; close tab kills the Mac-side shell.
