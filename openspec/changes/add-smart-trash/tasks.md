# Tasks: add-smart-trash

> Gate: no task starts until this change and the design doc are human-accepted
> and Fiple 1.0 has shipped. All work on `feat/smart-trash`; never push `main`.

## 1. FipleKit core (macOS)

- [ ] 1.1 `TrashCandidateStore`: candidate model (id, path, size, dates,
      deadline), keep-list, JSON persistence, injected clock; unit tests for
      candidacy, keep-exclusion, and persistence round-trip.
- [ ] 1.2 `StaleFileScanner`: scan granted folders via
      `contentAccessDateKey`, threshold filter, auto-evict used/missing
      candidates; unit tests with temp directories + fake clock.
- [ ] 1.3 Deadline enforcement: expiry → `FileManager.trashItem`, pre-move
      re-validation, catch-up on launch; unit tests (temp dirs; verify file
      lands in Trash / eviction on re-use).

## 2. Wire protocol

- [ ] 2.1 New `Messages` cases: `trashCandidates` push, `trashThumbnail`
      request/response, `trashAction(ids:decision:)` + typed result; codec
      round-trip tests.
- [ ] 2.2 Mac server handling: server-authoritative id resolution, snapshot
      push on connect and after changes; loopback tests.

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
