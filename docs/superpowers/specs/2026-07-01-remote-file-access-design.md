# Fiple — Off-LAN Remote File Access (Design)

> type: design (brainstorm output)
> status: draft
> date: 2026-07-01
> author: maksat + Claude
> relates-to: brd/fiple-mvp.md, adr/0002-lan-transport-security-model.md,
>   prd/fiple-remote-tiles.md

---

## Problem

You leave your MacBook at home and go to work. A file you need (e.g. today's
presentation) lives on the Mac. Today Fiple only works on the **same Wi-Fi
network** (Bonjour + plaintext TCP, ADR-0002), so from work you can reach
nothing. We want: **from anywhere, pull a recent file off the Mac to the
phone** — even when the Mac is asleep or off.

This is explicitly *not* screen mirroring / remote desktop. The user needs the
**data**, not a laggy picture of a screen. Live screen streaming over the
internet would require relay/TURN infrastructure and contradicts the project's
no-backend posture; it is out of scope.

## Decisions (locked during brainstorm)

| Decision | Choice |
| --- | --- |
| Scope (v1) | **Read-only file download.** Browse + pull a file to the phone. No remote tile execution, no upload-back. |
| Folder coverage | **Standard folders**: Desktop, Documents, Downloads. |
| Monetization | **Free** feature (not gated behind Fiple Pro). |
| Mac-offline behavior | **Pre-upload (cache).** Recent files are already in iCloud, so download works even when the Mac is off. |
| Pre-upload scope | **Bounded recent-files cache** (variant A), not a full mirror. |
| Favorites | **Pinned files** are exempt from eviction, with their own quota. |

## Non-negotiable safety invariant

> **Fiple performs read-only operations on the Mac filesystem. Under no
> circumstance (eviction, feature disable, error) does this feature delete or
> modify files on the Mac disk. Deletion affects only the cache copies stored
> in CloudKit.**

Two distinct concepts, never conflated:
- **Original** — the file on the Mac disk. Fiple only *reads* it to make a copy.
- **Cache copy** — a separate copy in CloudKit. Only this is ever evicted.

The worst case is that an *old* file becomes temporarily un-downloadable from
the phone while the Mac is off. The original is always safe.

---

## Architecture

No custom server. Transport is the user's **private CloudKit database**, tied to
their Apple ID.

```
┌─────────────── Mac (menu-bar agent) ───────────────┐
│  FSEvents watcher: Desktop / Documents / Downloads  │
│            │                                        │
│            ▼                                        │
│   RecentFilesCache (budget: N files / X GB / 30d)   │
│     • fresh file    → upload CKAsset + metadata     │
│     • over budget   → evict oldest cache copy       │
└────────────────────┬───────────────────────────────┘
                     │ writes to private DB
                     ▼
        ┌──────── iCloud / CloudKit private DB ────────┐
        │  RemoteFile: name, folder, size, date,       │
        │  thumbnail, CKAsset (payload)                │
        └────────────────────┬─────────────────────────┘
                             │ reads / downloads
                             ▼
┌──────────────── iPhone (Fiple) ─────────────────────┐
│  "Files" — recent files by folder + sync status     │
│  tap → download CKAsset → open / share              │
└─────────────────────────────────────────────────────┘
```

Why this shape:
- Mac off → file already in iCloud → download still works (the reason we chose
  pre-upload).
- Only *recent* files → iCloud quota stays bounded, privacy blast radius smaller.
- CloudKit private DB is encrypted by Apple in transit and at rest → removes the
  plaintext concern from ADR-0002 without a self-hosted relay.

## Identity — how devices connect (no in-app login)

There is **no Fiple account and no separate login**. The feature rides on the
device's existing iCloud sign-in.

- The developer enables **CloudKit** for the app → one shared container
  (e.g. `iCloud.com.fiple.app`) used by both the macOS and iOS apps.
- Each app writes to / reads from `CKContainer.privateCloudDatabase`, which is
  automatically scoped to the Apple ID signed in **on that device**.
- Mac and iPhone "find" each other because they are literally the **same iCloud
  account** — Apple matches them; no pairing code, no shared Wi-Fi needed.
- Requirement: **same Apple ID on both devices** with iCloud enabled. If the IDs
  differ or iCloud is off, show a clear message ("Sign in to the same Apple ID
  on both devices").

The LAN-pairing analog here is simply *"are both devices on one Apple ID"* — not
a code entry.

---

## Data model (CloudKit)

Private database, one custom record type.

**`RemoteFile`** (CKRecord)

| Field | Type | Purpose |
| --- | --- | --- |
| `fileName` | String | e.g. "Q3-deck.key" |
| `sourceFolder` | String (enum) | `desktop` / `documents` / `downloads` |
| `relativePath` | String | path within the folder (tree rendering) |
| `sizeBytes` | Int64 | file size |
| `modifiedAt` | Date | last modified on the Mac |
| `contentType` | String | UTI (icon / preview selection) |
| `thumbnail` | CKAsset (small) | preview, when applicable |
| `payload` | CKAsset | the file itself |
| `sourceDeviceID` | String | which Mac (future: multiple Macs) |
| `isPinned` | Bool | favorited → exempt from eviction |
| `cacheGeneration` | Int64 | bookkeeping for eviction / cleanup |

- `recordName` = stable hash of `sourceDeviceID + sourceFolder + relativePath`.
  Updating the same file overwrites its record instead of creating duplicates.
- Metadata is light → the phone list loads fast; the heavy `payload` downloads
  only on tap.

---

## Mac agent behavior

Lives in the existing menu-bar app.

1. **Watcher** — subscribes to FSEvents for Desktop / Documents / Downloads. On
   create/modify, queues the file for re-evaluation.
2. **Selection** — the file enters the cache if it passes the budget and is not
   excluded.
3. **Upload** — uploads `payload` (+ `thumbnail`) as CKAssets and writes/updates
   the `RemoteFile` record.
4. **Eviction** — when the budget is exceeded, removes the oldest-by-`modifiedAt`
   cache copies from CloudKit. A file deleted from the Mac disk is also removed
   from the cache. (Originals are never touched — safety invariant.)

### Budget (defaults, configurable on Mac)

- Age: modified within the last **30 days**.
- Count: up to **200 files**.
- Size: up to **2 GB** total; single file up to **100 MB** (else skipped +
  flagged "too large").
- Eviction priority: oldest by `modifiedAt` first.

### Exclusions (never uploaded)

- Hidden/system files (`.DS_Store`), app/installer bundles (`.app`, `.dmg`),
  package directories (`.photoslibrary`, etc.).
- User's explicit ignore list (can exclude a subfolder).

### Master toggle

The whole feature is turned on/off on the Mac by a single switch, "Remote file
access." Turning it off purges the entire cache from CloudKit (originals
untouched).

---

## Favorites (pinned files)

- On the phone, a file has a **Pin** (⭐) action. A pinned file is **exempt from
  eviction** — never dropped by age (30d) or count (200).
- Technically: `isPinned` flag on `RemoteFile`. The phone sets it; the Mac agent
  honors it and keeps the copy cached even if the file hasn't changed in a while
  (the original is always on the Mac, so the agent can re-read and re-upload).
- Unpin → the file returns to the normal pool and obeys the budget again.

### Separate pinned budget (so favorites can't eat the quota)

- Up to **50 files** / **1 GB** total pinned; per-file cap still **100 MB**.
- At the limit, pinning shows "Favorites limit reached — unpin something."
- Pinned files have their **own** quota; they do not compete with the fresh pool
  (fresh files never evict pinned, and vice versa).

---

## iPhone UX

A new **"Files"** section (tab/screen alongside tiles).

- **List by folder** — Desktop / Documents / Downloads as sections; inside, fresh
  files with type icon, preview (if any), size, and date. Sorted newest first.
- **Favorites section** — pinned files pinned to the top, always visible; ⭐ badge;
  swipe / long-press to pin/unpin.
- **Tap a file → download** — CKAsset download progress, then:
  - **Open** (Quick Look / the appropriate app),
  - **Share** (system share sheet → work computer, messenger, email).
- **Sync status** — a clear header line: "Updated just now" / "Updated N min ago"
  (last Mac upload); if the Mac has been offline a while, "Mac offline — showing
  files as of …".
- **Search** — by filename within the cache.
- **Empty state (feature off)** — "Turn on Remote file access in Fiple on your
  Mac."
- **Boundary transparency** — a small caption "Showing recent files (up to
  200 / 2 GB)" so nothing feels silently missing.

The phone only browses and downloads — no editing, no upload-back (v1). Fully in
line with the PRD principle "the phone is purely a remote."

---

## Security & governance

### Security

- Transport is the private CloudKit DB, scoped to the user's Apple ID, encrypted
  by Apple in transit and at rest. No self-hosted server, no Fiple accounts, no
  relay.
- The cache is reachable only by devices under the same Apple ID. Compromise
  blast radius = the *recent* files of standard folders (not the whole disk) —
  precisely why variant A over "entire home directory."
- Read-only invariant (above): deletion only ever touches the CloudKit cache.

### New ADR required (blocking, human-only acceptance)

**ADR-0004: Off-LAN File Access via CloudKit.** Triggered by ADR-0002's own
criteria (#1 "beyond a trusted personal LAN" and #3 "cross-network/relay"). It
records: CloudKit as the transport for this feature, encryption via iCloud, the
cache boundaries, and the read-only invariant. It **amends/extends** ADR-0002
(which still governs the LAN remote) — it does not repeal it.

### Documents to author (all `draft` — acceptance is human-only)

1. `docs/design-docs/adr/0004-offlan-file-access-cloudkit.md`
2. `docs/design-docs/prd/fiple-remote-file-access.md`
3. OpenSpec change `openspec/changes/add-remote-file-access/` with capability
   `remote-file-access` (`proposal.md`, `tasks.md`, `design.md`,
   `specs/remote-file-access/spec.md` with WHEN/THEN scenarios).
4. This design doc (committed now).

---

## Testing strategy

- **Unit** — budget/eviction (age, count, size), pin logic and its separate
  quota, stable `recordName` (no duplicates on re-upload), exclusion filters.
- **Read-only invariant** — a test asserting the agent never issues a
  delete/write against the disk.
- **Loopback** — an upload → list → download scenario over a mocked CloudKit
  (no real iCloud in CI).

---

## Out of scope (v1)

- Screen mirroring / remote desktop.
- Remote tile execution from off-LAN (candidate for a later iteration; would
  extend today's LAN remote — see variant C in brainstorm).
- Upload-back / two-way sync (write to the Mac from the phone).
- Multiple Macs (schema leaves room via `sourceDeviceID`, but UX is single-Mac).
- Editing files on the phone.

## Open questions

| Question | Owner | Status |
| --- | --- | --- |
| Are the budget defaults (200 / 2 GB / 30d) right after real-world use? | maksat | open |
| Should thumbnails be generated for all types or a curated set (docs, images, PDFs, Keynote/PPT)? | maksat | open |
| How to surface iCloud-quota-full errors on the Mac gracefully? | maksat | open |
| Do we need push notification to the phone when a pinned file finishes (re)uploading? | maksat | open |
