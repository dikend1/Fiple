# Smart Trash — design (draft)

Status: draft — pending human acceptance (per repo governance). Target: Fiple 1.1+, branch `feat/smart-trash`. No code before doc acceptance.

## Idea

The Mac finds stale files (not opened for a long time) in Downloads and Desktop, lists them as deletion candidates with a countdown, and the iPhone reviews them one at a time in a full-screen swipe deck (photo-cleaner style): swipe left → into an in-app staging basket, swipe right → keep. Nothing touches the Mac until the user confirms the basket with "Empty". Unreviewed candidates auto-move to the **system macOS Trash** when their countdown expires — always recoverable, never permanently deleted by Fiple.

## Chosen approach: virtual candidate list ("Variant A")

Files are **never physically moved** until the user acts or the deadline expires. The "Smart Trash" is a list, not a folder — so nothing on the Mac breaks (no broken recents, no name conflicts, nothing vanishing before review).

Lifecycle of one file:
1. File sits untouched in Downloads/Desktop for the staleness threshold (default 60 days, based on macOS last-open date).
2. Daily scan adds it to the candidate list with a review deadline (default +7 days).
3. Phone shows it as a card in the review deck (thumbnail, name, size, "not opened for 2 months, 5 days left").
4. User swipes left → staged in the in-app basket; "Empty (N)" commits the batch → system Trash. Swipe right → excluded forever ("keep"). Undo steps back through this session's swipes until a decision is committed.
5. No action by the deadline → Mac auto-moves it to the system Trash and posts a notification.
6. If the file is opened/modified/moved while a candidate, it silently leaves the list.

## Components

- **`StaleFileScanner`** (FipleKit, macOS): daily scan of user-granted folders; staleness via last-open metadata; emits candidates.
- **`TrashCandidateStore`** (FipleKit, macOS): persisted candidates (path, size, deadline), keep-list of exclusions, deadline enforcement → `FileManager.trashItem` (system Trash). Missed deadlines (Mac asleep) are enforced on next launch.
- **Wire messages** (FipleKit): new message types on the existing LAN tile channel — list candidates, fetch thumbnail (QuickLook JPEG ~50–100 KB), action(trash/keep, ids). No new transport, no backend.
- **iOS Trash screen**: full-screen swipe deck (one card per candidate: thumbnail, name, size, staleness + countdown). Swipe left = stage for trash (red ✕ overlay), swipe right = keep (green ✓ overlay); mirrored ✕ / ✓ buttons plus an Undo button that steps back through this session's decisions. Header shows "reviewed/total" progress and a basket icon with a staged count; the basket sheet lists staged files, lets the user return any card to the deck, and "Empty (N)" sends one batch `trash` action. Keep decisions are sent as a batch on commit or when leaving the screen. Staging is in-memory only — quitting mid-review discards uncommitted decisions and those files simply remain candidates. The next 2–3 card thumbnails are prefetched so the deck stays smooth. Entry card on Home with a badge count.

## Sandbox & App Store

- Feature off by default. Enabling shows a standard folder-picker; access to Downloads/Desktop is stored as security-scoped bookmarks.
- Fiple never permanently deletes — only the system Trash.
- Files that get used again auto-leave the list.

## Notifications (no backend — honest limits)

- Mac: local notification when deadlines approach/fire ("12 files move to Trash in 5 days").
- iPhone: badge on the Home Trash card when connected; on each sync the app schedules a local reminder for ~2 days before the nearest deadline. No off-LAN push — impossible without a server.

## Defaults / settings

- Staleness threshold: 60 days (configurable: 30/60/90).
- Review window: 7 days.
- Scanned folders: Downloads + Desktop (user can add/remove folders via picker).

## Testing

FipleKit unit tests: temp directories + injected clock for scanner/store (candidacy, deadline expiry, un-stale removal, keep-list); loopback message tests like existing pairing/terminal suites.

## Governance / rollout

- 1.0 (in review) untouched; work on `feat/smart-trash`, never push to main.
- Next artifacts: OpenSpec change `add-smart-trash` (proposal/tasks/design/spec with WHEN/THEN scenarios), PRD delta — all draft until human acceptance.
- Candidate Fiple Pro feature (decide with the paywall, does not affect this design).
