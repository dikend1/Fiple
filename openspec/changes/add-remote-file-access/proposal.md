# Change: Add off-LAN remote file access

> New (not-yet-implemented) work. Blocked on human acceptance of **ADR-0004**
> (off-LAN transport via CloudKit) and PRD `fiple-remote-file-access.md`. Do not
> implement until accepted.

## Why

Fiple is LAN-only today (ADR-0002): away from home, the phone reaches nothing. A
common real need is retrieving a file that lives on the Mac when you are on a
different network and the Mac may be asleep or off — the "forgot my laptop at
home, I need today's presentation" case. Screen mirroring would need relay
infrastructure and only shows a laggy picture; the user needs the **data**. This
change lets the phone pull a recent file off the Mac from anywhere, read-only,
with no server and no Fiple account.

## What Changes

- **Mac recent-files cache** — a background agent watches Desktop / Documents /
  Downloads (FSEvents) and keeps a **bounded** set of recent files in the user's
  **private CloudKit** database: defaults ≤ 30 days, ≤ 200 files, ≤ 2 GB total,
  ≤ 100 MB/file. Over-budget copies are evicted oldest-first. System/hidden files
  and bundles are excluded.
- **Pinned favorites** — the phone can pin a file so it is exempt from eviction,
  within a separate budget (≤ 50 files / 1 GB).
- **Identity via Apple ID** — no in-app login; the private DB is scoped to the
  device's iCloud account. Same Apple ID on both devices ⇒ they interoperate.
  Mismatch / iCloud-off ⇒ a clear message.
- **Phone Files browser** — a new "Files" section: recent files by folder + a
  Favorites section, sync status, search, download → open / share. Browse and
  download only.
- **Read-only safety invariant** — the Mac agent only reads originals; no path
  (eviction, disable, error) deletes or modifies files on the Mac disk. Deletion
  touches only CloudKit cache copies.
- **Master switch** — one Mac toggle enables the feature; off purges the cache.

This adds a **new transport** (CloudKit) for this feature only; the LAN control
channel (ADR-0002) is unchanged. No relay/TURN, no accounts.

## Impact

- New capability spec: `remote-file-access`.
- Affected code (planned): `FipleKit` (cache/budget/eviction logic, CloudKit
  record model, read-only file reader), `Apps/FipleMac` (FSEvents watcher,
  CloudKit sync agent, settings toggle), `Apps/FipleiOS` (Files browser, CloudKit
  fetch/download, pin actions).
- New capabilities/entitlements: iCloud + CloudKit; App Store data-use /
  privacy-manifest disclosure for the CloudKit store.
- Related design docs:
  - docs/design-docs/adr/0004-offlan-file-access-cloudkit.md (new — cited)
  - docs/design-docs/prd/fiple-remote-file-access.md (new — cited)
  - docs/superpowers/specs/2026-07-01-remote-file-access-design.md (brainstorm)
