# Design — Off-LAN remote file access

> Technical shape for the `remote-file-access` capability. Full rationale and
> alternatives are in ADR-0004 and the brainstorm design doc
> (`docs/superpowers/specs/2026-07-01-remote-file-access-design.md`).

## Transport & identity

- **CloudKit private database**, one shared container across the macOS and iOS
  apps. Records/assets are scoped to the Apple ID signed in on each device — no
  in-app login. Interop requires the **same Apple ID + iCloud** on both.
- No self-hosted server, no relay/TURN, no Fiple accounts. Encryption in transit
  and at rest is handled by Apple.

## Data model

One custom record type, `RemoteFile` (private DB):

| Field | Type | Purpose |
| --- | --- | --- |
| `fileName` | String | display name |
| `sourceFolder` | String enum | `desktop` / `documents` / `downloads` |
| `relativePath` | String | path within the folder (tree) |
| `sizeBytes` | Int64 | size |
| `modifiedAt` | Date | last-modified on the Mac |
| `contentType` | String | UTI (icon / preview) |
| `thumbnail` | CKAsset? | small preview when applicable |
| `payload` | CKAsset | the file itself |
| `sourceDeviceID` | String | which Mac (future multi-Mac) |
| `isPinned` | Bool | favorited → exempt from eviction |
| `cacheGeneration` | Int64 | eviction/cleanup bookkeeping |

- `recordName` = stable hash of `sourceDeviceID + sourceFolder + relativePath`,
  so re-uploading the same file updates its record (no duplicates).

## Mac agent

1. **Watcher** — FSEvents on the three folders; enqueue changed paths.
2. **Selection** — admit a file if it passes the budget and is not excluded
   (hidden/system, `.app`/`.dmg`, package dirs, user ignore list).
3. **Upload** — write/update `RemoteFile` with `payload` (+ `thumbnail`).
4. **Eviction** — over budget ⇒ delete oldest-by-`modifiedAt` cache copies from
   CloudKit; a file removed from disk is removed from the cache.

### Budgets (configurable defaults)

- Fresh pool: ≤ 30 days, ≤ 200 files, ≤ 2 GB total, ≤ 100 MB/file.
- Pinned pool (separate): ≤ 50 files, ≤ 1 GB, ≤ 100 MB/file.
- The pools do not compete: fresh eviction never drops pinned, and vice versa.

### Read-only invariant (enforced)

The agent exposes only read operations against the Mac filesystem. No code path
performs a disk delete/write. This is covered by a dedicated test asserting the
file-reader interface has no mutating calls and eviction targets CloudKit only.

## iPhone

- **Files** section: folder sections (newest first) + a Favorites section (pinned
  on top). Type icons, previews, size, date, filename search.
- **Download** a tapped file's `payload` with progress → **Open** (Quick Look) or
  **Share** (system sheet). No edit / delete / upload.
- **Pin/unpin** sets `isPinned`; at the pinned limit, show "Favorites limit
  reached — unpin something."
- **Status**: last-refresh line; "Mac offline — showing files as of …" when the
  Mac hasn't synced recently.
- **Unavailable states**: feature off on Mac → guidance to enable it; Apple ID
  mismatch / iCloud off → "sign in to the same Apple ID."

## Failure handling

- **iCloud quota full (Mac)** — surface a clear Mac-side error; pause uploads;
  do not fail silently. Never touches originals.
- **Asset download fails (phone)** — retryable error with the file left in the
  list.
- **Large file (> 100 MB)** — skipped from the cache and flagged; not an error.

## Testing

- **Unit** (FipleKit): budget admission + eviction (age/count/size), pin logic +
  separate quota, stable `recordName` dedupe, exclusion filters.
- **Read-only invariant**: assert no disk-mutating path exists; eviction targets
  CloudKit only.
- **Loopback**: upload → list → download over a mocked CloudKit (no real iCloud
  in CI).
