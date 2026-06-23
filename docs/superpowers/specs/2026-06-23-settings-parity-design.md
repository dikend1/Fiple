# Settings parity (iOS + Mac) — design

Status: draft
Date: 2026-06-23
Topic: Make the Settings screen on both apps fully functional and structurally
matched, so the apps are App-Store-submittable.

## Problem

The iOS Settings screen is mostly non-functional. Its own source comment says
*"All controls are presentation-only stand-ins for now."* Concretely, only
Disconnect works; Appearance, Launch at Login, Notifications, Default Browser,
Language, About Fiple, Help & Support, Privacy Policy and Terms of Service do
nothing. The Mac Settings screen is fully functional but minimal (Connection,
Version, Disconnect, Quit) and lacks the About/Legal links.

This blocks an App Store launch:

- Apple rejects apps with non-functional placeholder controls (Guideline 2.1).
- Apple requires a working Privacy Policy link (and conventionally Terms).

The two screens should also read as one product: the same section structure,
adapted to each platform's role (Mac is the host, iPhone is the remote).

## Goals

- Every visible control in Settings on both platforms performs a real action.
- Both screens share the section order: **Connection/Devices → Preferences → About**.
- Privacy Policy, Terms of Service, and Help & Support open real URLs on both.
- No change to styles, palettes, layout, or any screen other than Settings.

## Non-goals

- No dark-mode / theme switching. Both themes are intentionally fixed-light (the
  Mac sidebar is explicitly "fixed regardless of system appearance"). A working
  Appearance control would require reworking the palette — i.e. changing the UI,
  which is out of scope. The Appearance row is removed, not wired up.
- No in-app notifications feature; the Notifications row is removed.
- No new visual components or restyling. Existing row components are reused and
  given real actions.

## Decisions (confirmed with user)

- Remove rows that don't apply to a remote/host app rather than fake them.
- Legal/support links use the user's domain `fiple.app`.
- "Matching" means same sections in the same order, with platform-appropriate
  rows inside — not a byte-identical row list.

## Design

### Shared link/source of truth — `FipleLinks` (FipleKit)

Add a small enum to the shared `FipleKit` module so both apps reference one
source of truth (mirrors how `Theme` is the single token source per app):

```swift
// FipleKit/Sources/FipleKit/AppInfo/FipleLinks.swift
public enum FipleLinks {
    public static let privacy = URL(string: "https://fiple.app/privacy")!
    public static let terms   = URL(string: "https://fiple.app/terms")!
    public static let support = URL(string: "https://fiple.app/support")!
}
```

Unit-tested in `FipleKitTests`: each URL is non-nil, uses `https`, and has host
`fiple.app`. Runs under the existing `swift test`.

### iOS — `Apps/FipleiOS/Views/Settings/SettingsView.swift`

| Section | Row | Behaviour |
| --- | --- | --- |
| Connected Devices | Your Mac (name + status) | Unchanged: confirmation alert → `controller.disconnect()` |
| Connected Devices | Pair New Mac | Unchanged: `controller.disconnect()` to return to pairing |
| Preferences | Clear Launch History | Confirmation alert → `controller.clearRecents()` (existing real method) |
| About | Version `x.y (b)` | Display-only value read from `Bundle.main` (parity with Mac) |
| About | Help & Support | Open `FipleLinks.support` |
| About | Privacy Policy | Open `FipleLinks.privacy` |
| About | Terms of Service | Open `FipleLinks.terms` |

Removed: Appearance, Launch at Login, Notifications, Default Browser, Language,
the empty "About Fiple" row.

Implementation notes:

- `SettingsRow` currently wraps an empty `Button {}`. Add an `action: () -> Void`
  parameter (default no-op) so rows can perform real work. No visual change.
- Links open via the SwiftUI `openURL` environment value.
- "Clear Launch History" uses the same `.alert` pattern already present for
  unpair. The state `launchAtLogin` and the `SettingsToggleRow` component become
  unused on iOS; `SettingsToggleRow` is removed (no remaining iOS use).

### Mac — `Apps/FipleMac/Views/Settings/SettingsView.swift`

| Section | Row | Behaviour |
| --- | --- | --- |
| Connection | Connection (status) | Unchanged |
| Connection | Disconnect iPhone | Unchanged: shown when `server.status == .connected` → `server.disconnect()` |
| Preferences | Launch at Login | `SMAppService.mainApp` register/unregister; reflects `.status == .enabled` |
| About | Version `x.y (b)` | Unchanged |
| About | Help & Support | Open `FipleLinks.support` |
| About | Privacy Policy | Open `FipleLinks.privacy` |
| About | Terms of Service | Open `FipleLinks.terms` |
| (footer) | Quit Fiple | Unchanged: `NSApplication.shared.terminate(nil)` |

Implementation notes:

- Reuse the existing `settingRow(title:value:)` look. Add a tappable link-row
  variant and a toggle-row variant in the same visual style — no new design.
- Launch at Login: `import ServiceManagement`. On appear, read
  `SMAppService.mainApp.status`. Toggle calls `register()` / `unregister()`
  inside `do/catch`; on failure, revert the toggle and surface a brief inline
  message. Works under App Sandbox (Mac App Store) and Developer ID.
- Links open via `openURL` environment (or `NSWorkspace.shared.open`).

### Error handling

- Link rows: `openURL` handles unreachable URLs at the OS level; no in-app error
  state needed beyond what the system shows.
- Launch at Login: register/unregister can throw; catch, revert toggle to actual
  `status`, and show a one-line message. Never leave the toggle out of sync with
  the real service state.
- Clear history / disconnect: already idempotent; confirmation alert prevents
  accidental taps.

## Testing & verification

- `xcodegen generate`
- `cd FipleKit && swift test` — new `FipleLinks` test + existing suite green.
- `xcodebuild ... FipleMac ... build` and `xcodebuild ... FipleiOS ... build`.
- iOS: launch in simulator, screenshot Settings, verify every row acts (links
  open, Clear History prompts and clears, Version shows).
- Mac: manual check of Launch at Login toggle (system service; not unit-testable)
  and that links open.

## Files touched

- `FipleKit/Sources/FipleKit/AppInfo/FipleLinks.swift` (new)
- `FipleKit/Tests/FipleKitTests/FipleLinksTests.swift` (new)
- `Apps/FipleiOS/Views/Settings/SettingsView.swift`
- `Apps/FipleMac/Views/Settings/SettingsView.swift`

Nothing else is modified.
