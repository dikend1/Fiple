# Design: Smart Trash

Full narrative design: docs/superpowers/specs/2026-07-08-smart-trash-design.md.
This file records the technical decisions.

## Decisions

1. **Virtual candidate list, not a staging folder.** Files stay in place until
   the user acts or the deadline expires. Rejected alternative (physically
   moving stale files into a "Fiple Trash" folder immediately) breaks recents /
   in-progress downloads, risks name conflicts on restore, and reads as
   data-loss behavior in App Store review.
2. **System Trash is the only destructive sink.** Both explicit "Move to Trash"
   and deadline expiry call `FileManager.trashItem(at:)`. Fiple never
   permanently deletes; recovery is always the stock macOS Trash.
3. **Staleness = last-open date.** `URLResourceKey.contentAccessDateKey`
   (fallback: content-modification date when access date is unavailable).
   Threshold default 60 days; review window 7 days.
4. **Auto-evict on use.** The daily scan and pre-enforcement check drop any
   candidate whose file was opened/modified after candidacy or no longer exists
   at its recorded path.
5. **Folder access via security-scoped bookmarks.** Feature off by default;
   enabling presents `NSOpenPanel` for Downloads/Desktop (or user's choice);
   bookmarks persist across launches. Sandbox-compatible for MAS.
6. **Transport reuse.** New JSON message cases on the existing plaintext LAN
   channel (ADR-0002 trade-off applies unchanged): `trashCandidates` snapshot
   push, `trashThumbnail(id:)` request/response (QuickLookThumbnailing JPEG,
   ~50–100 KB, fetched lazily per visible cell), `trashAction(ids:, keep|trash)`
   with a typed result. Server-authoritative: the phone sends candidate ids
   only; the Mac resolves them against its own store.
7. **Keep-list.** "Keep" stores a permanent exclusion (path + file identity) in
   `TrashCandidateStore`; excluded files are skipped by future scans.
8. **Persistence.** Candidate list, keep-list, bookmarks, and settings persist
   on the Mac (Application Support JSON via existing store patterns); the phone
   holds only a synced snapshot.
9. **Swipe-deck review with local staging (supersedes the earlier grid +
   multi-select).** The phone reviews candidates one at a time in a full-screen
   card deck: swipe left = stage for trash, swipe right = keep. Staged ids
   accumulate in an in-app basket; only "Empty (N)" sends
   `trashAction(ids:, trash)` as one batch, and keep ids flush as one
   `trashAction(ids:, keep)` batch on commit or screen exit. Undo pops the last
   uncommitted decision (either direction) — purely local, no wire message.
   The basket persists on the phone: the session lives on the connection
   controller (screen re-entry keeps it) and staged ids are saved locally,
   restored against the next snapshot after a relaunch — staged files never
   silently reappear in the deck. On the Mac they stay ordinary candidates
   (deadlines keep ticking) until committed. A fresh pairing clears the saved
   basket. No protocol change: the existing snapshot/thumbnail/action
   messages already cover this UI (thumbnails prefetch 2–3 cards ahead instead
   of per visible cell).
10. **Notifications.** Mac: `UserNotifications` local notification when items
   are ≤2 days from deadline and when auto-trash fires. iOS: on each sync,
   reschedule one local notification for (nearest deadline − 2 days).

## Open questions

- Pro gating (decided with the paywall change, not here).
