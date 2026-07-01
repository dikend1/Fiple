# Fiple — Off-LAN Remote File Access (PRD)

> type: prd
> status: draft
> date: 2026-07-01
> deciders: []
> relates-to: brd/fiple-mvp.md, adr/0004-offlan-file-access-cloudkit.md,
>   prd/fiple-remote-tiles.md

---

## Overview

Today Fiple is a LAN-only remote for the Mac. This PRD adds the ability to
**retrieve a recent file from the Mac to the phone from anywhere** — including a
different network, and even when the Mac is asleep or off. The motivating case:
you leave your MacBook at home, go to work, and need a file that lives on it
(e.g. today's presentation).

The Mac stays the source of truth. The phone only **browses and downloads** — it
never edits, deletes, or uploads files back. This preserves the BRD/PRD principle
that "the phone is purely a remote." Transport and trust are defined in ADR-0004
(private CloudKit, keyed to the user's Apple ID; no server, no Fiple account).

This is a **free** feature.

---

## User-Observable Properties

- **Works from anywhere** — file retrieval does not require the same Wi-Fi; it
  works over cellular / any network.
- **Works when the Mac is off** — recent files are pre-cached in the user's
  private iCloud, so download succeeds even with the Mac asleep or shut down.
- **No login** — the feature uses the Apple ID already signed in on each device.
  It works when the Mac and iPhone share the same Apple ID with iCloud enabled.
- **Recent files only** — the phone shows a bounded, recent set from Desktop,
  Documents, and Downloads (not the whole disk), with the limits made visible.
- **Pinned favorites** — the user can pin a file so it is never dropped from the
  cache, within a separate favorites limit.
- **Download, open, share** — tapping a file downloads it, then it can be opened
  (Quick Look / the right app) or sent onward via the system share sheet.
- **Honest sync status** — the phone shows when the cache was last refreshed and
  flags when the Mac has been offline.
- **Read-only safety** — nothing the user does on the phone can change or delete
  files on the Mac. (See the safety invariant below.)
- **Mac master switch** — the whole feature is turned on/off on the Mac; off
  purges the cloud cache.

## Safety Invariant (non-negotiable)

The feature performs **read-only** operations on the Mac filesystem. No path —
eviction, disabling the feature, or an error — ever deletes or modifies files on
the Mac disk. Eviction affects only cache copies stored in CloudKit. The worst
case is that an *old* file is temporarily un-downloadable while the Mac is off;
the original is always safe.

---

## Core Flow

1. On the Mac, the user turns on "Remote file access." The Mac begins keeping a
   bounded cache of recent files from Desktop / Documents / Downloads in the
   user's private iCloud.
2. Later, away from home (Mac asleep), the user opens Fiple on the phone and sees
   the recent files grouped by folder, plus a Favorites section.
3. The user taps the presentation; the phone downloads it from iCloud.
4. The user opens it in Quick Look and shares it to their work computer.
5. Back home, the user edits a different file; the Mac refreshes its cache copy
   automatically. An older file rolls out of the cache as the budget fills — its
   original stays on the Mac untouched.

---

## Success Criteria

- [ ] A file modified on the Mac appears in the phone's list and downloads
  successfully from a different network.
- [ ] With the Mac asleep/off, a recently-cached file still downloads to the
  phone.
- [ ] A pinned file is never evicted while pinned, subject to the favorites
  limit.
- [ ] The phone offers no way to edit, delete, or upload files to the Mac.
- [ ] No feature path deletes or modifies an original file on the Mac disk.
- [ ] With mismatched Apple IDs / iCloud off, the phone shows a clear "sign in to
  the same Apple ID" message instead of an empty or broken screen.
- [ ] The phone shows last-refresh time and an offline indicator when the Mac is
  out of contact.

## Constraints

- Read-only over the Mac filesystem (safety invariant).
- Coverage is Desktop / Documents / Downloads only, bounded by budget.
- Requires the same Apple ID + iCloud on both devices.
- Consumes the user's iCloud quota; quota-full is surfaced, not silent.
- The phone renders what the Mac has cached; it holds no authoritative file data.

## Out Of Scope

- Screen mirroring / remote desktop.
- Remote tile execution from off-LAN (possible later; would extend the LAN
  remote).
- Upload-back / two-way sync / editing on the phone.
- Access to arbitrary folders beyond the standard three.
- Multiple Macs in the UI (data model leaves room; UX is single-Mac for v1).

## Open Questions

| Question | Owner | Status |
| --- | --- | --- |
| Are the default budgets (200 / 2 GB / 30 d; pins 50 / 1 GB) right after real use? | maksat | open |
| Thumbnails for all types or a curated set (images, PDF, Keynote/PPT, docs)? | maksat | open |
| Do we push-notify the phone when a pinned file finishes (re)uploading? | maksat | open |
| How to present iCloud-quota-full gracefully on the Mac? | maksat | open |
