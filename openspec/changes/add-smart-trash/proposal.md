# Change: Add Smart Trash (stale-file cleanup reviewed from the phone)

> Status: draft — no implementation until the design doc and this change pass
> the human-acceptance gate, and not before the 1.0 App Store release.
> Work happens on branch `feat/smart-trash`; never pushed to `main`.

## Why

Downloads and the Desktop accumulate screenshots and one-shot documents that are
never opened again. Cleaning them up is tedious enough that nobody does it.
Fiple already pairs the phone to the Mac over LAN; the phone is the ideal place
to triage this backlog in idle moments. No existing Mac cleaner offers
phone-based review.

## What Changes

- **Mac: stale-file scanning** — a daily scan of user-granted folders
  (Downloads + Desktop by default) flags files not opened for a threshold
  (default 60 days, from macOS last-open metadata) as deletion candidates with
  a 7-day review deadline. Files are **not moved**; the "trash" is a virtual
  candidate list.
- **Mac: deadline enforcement** — candidates unreviewed by their deadline move
  to the **system macOS Trash** (recoverable; Fiple never deletes permanently).
  Missed deadlines (Mac asleep) are enforced at next launch. A candidate that
  is opened, modified, or moved leaves the list automatically.
- **Wire protocol** — new message types on the existing LAN channel: candidate
  list sync, thumbnail fetch (QuickLook JPEG), and `trash`/`keep` actions by id.
- **iOS: Trash review screen** — Photos-style thumbnail grid with multi-select
  and bottom actions "Move to Trash" / "Keep"; per-item countdown; badge on a
  Home entry card. "Keep" excludes the file from future scans permanently.
- **Notifications** — Mac local notification before deadlines fire; iOS
  schedules a local reminder (~2 days before the nearest deadline) at each
  sync. No off-LAN push (no backend, per project policy).
- **Settings (Mac)** — feature off by default; enabling opens a folder picker
  (security-scoped bookmarks); threshold configurable (30/60/90 days).

## Impact

- Affected specs: new capability `smart-trash`. No changes to `pairing`,
  `tile-execution`, or the transport architecture (ADR-0002 unchanged —
  candidate metadata/thumbnails ride the existing LAN channel).
- Affected code (planned): `FipleKit` (`StaleFileScanner`,
  `TrashCandidateStore`, new `Messages` cases), `Apps/FipleMac`
  (settings section, folder access, notifications), `Apps/FipleiOS`
  (Trash grid screen, Home card, local reminders).
- Related design doc: docs/superpowers/specs/2026-07-08-smart-trash-design.md
  (draft). Candidate Fiple Pro feature — gating decided with the paywall work,
  out of scope here.
