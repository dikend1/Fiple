# Tasks: add-smart-trash

> Gate: no task starts until this change and the design doc are human-accepted
> and Fiple 1.0 has shipped. All work on `feat/smart-trash`; never push `main`.

## 1. FipleKit core (macOS)

- [x] 1.1 `TrashCandidateStore`: candidate model (id, path, size, dates,
      deadline), keep-list, JSON persistence, injected clock; unit tests for
      candidacy, keep-exclusion, and persistence round-trip.
      *Evidence: `TrashCandidateStoreTests` 5/5 green (2026-07-08).*
- [x] 1.2 `StaleFileScanner`: scan granted folders via
      `contentAccessDateKey`, threshold filter, auto-evict used/missing
      candidates; unit tests with temp directories + fake clock.
      *Evidence: `StaleFileScannerTests` 4/4 green (2026-07-08).*
- [x] 1.3 Deadline enforcement: expiry → `FileManager.trashItem`, pre-move
      re-validation, catch-up on launch; unit tests (temp dirs; verify file
      lands in Trash / eviction on re-use).
      *Evidence: `TrashDeadlineEnforcerTests` 3/3 green; full suite 70 tests
      green (2026-07-08). Launch catch-up wired in task 3.x app integration.*

## 2. Wire protocol

- [x] 2.1 New `Messages` cases: `trashCandidates` push, `trashThumbnail`
      request/response, `trashAction(ids:decision:)` + typed result; codec
      round-trip tests.
      *Evidence: `TrashWireTests` 3/3 green, incl. unknown-decision → keep
      (2026-07-08).*
- [x] 2.2 Server-authoritative handling: `TrashReviewHandler` resolves ids
      against the Mac's own store, re-validates files before trashing, and
      reports unknown ids in the typed result.
      *Evidence: `TrashReviewHandlerTests` 3/3 green — incl. "used after the
      phone's snapshot is never trashed"; full suite 76 tests green
      (2026-07-08). Snapshot push on connect wires in task 3.x.*

## 3. Mac app

- [ ] 3.1 Settings section: enable toggle → `NSOpenPanel` folder grant
      (security-scoped bookmarks), threshold picker (30/60/90), granted-folder
      list; off-by-default; disable clears candidates.
- [ ] 3.2 Local notifications: ≤2-days-to-deadline reminder and auto-trash
      summary.
- [ ] 3.3 Thumbnail generation via QuickLookThumbnailing (JPEG, cached).

## 4. iOS app

- [ ] 4.1 Home entry card with candidate-count badge.
- [ ] 4.2 Trash screen: thumbnail grid, multi-select, bottom bar
      "Move to Trash" / "Keep", per-item countdown, lazy thumbnail fetch.
- [ ] 4.3 Local reminder scheduling on each sync (nearest deadline − 2 days).

## 5. Verification & docs

- [ ] 5.1 `cd FipleKit && swift test` green; record evidence here.
- [ ] 5.2 On-device pass: enable → grant folders → candidates appear on phone →
      batch trash lands in macOS Trash → keep excludes → deadline auto-trash.
- [ ] 5.3 After ship: update `openspec/specs/` and `docs/architecture/`
      (implemented truth), then archive this change.
