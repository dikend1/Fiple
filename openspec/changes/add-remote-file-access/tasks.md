# Tasks — Add off-LAN remote file access

> **Status: code implemented ahead of acceptance at the owner's explicit
> direction** (the acceptance gate below was overridden by the user in-session).
> The FipleKit core is verified (`swift test`, 75 tests) and both apps build.
> What remains is genuinely gated on the owner: CloudKit container/entitlement
> provisioning (0.3) — until then the feature is inert (toggle defaults off,
> phone shows the iCloud-unavailable state). ADR-0004/PRD acceptance (0.1/0.2)
> is still formally pending.

## 0. Gate

- [ ] 0.1 Human accepts ADR-0004 (off-LAN via CloudKit). *(overridden to build early)*
- [ ] 0.2 Human accepts PRD `fiple-remote-file-access.md`. *(overridden to build early)*
- [ ] 0.3 CloudKit container + iCloud entitlement provisioned in the Apple
  Developer account. Entitlement *files* are done (iCloud/CloudKit keys and the
  read-only folder exceptions are in both `Fiple.entitlements`); what cannot be
  verified from the repo is the Developer-account provisioning itself.
  Note: the home-relative-path temporary exception must be replaced with
  security-scoped bookmarks **before App Store submission** (review risk).

## 1. Core model & budget (FipleKit) — done, tested

- [x] 1.1 `RemoteFile` record model + stable SHA-256 `recordName`. — `RemoteFile.swift`
- [x] 1.2 Budget engine: admission + oldest-first eviction (fresh pool) + separate
  pinned pool + per-file cap. — `CacheBudget.swift`, `CachePlanner.swift`
- [x] 1.3 Exclusion filter (hidden/system, bundles, user ignore list). — `FileExclusion.swift`
- [x] 1.4 Read-only reader (`FileReading`/`DiskFileReader`) + eviction targets
  CloudKit only (`RemoteFileCache`, `RemoteFileStore`).

## 2. Mac agent (Apps/FipleMac) — code done; entitlements pending (0.3)

- [x] 2.1 FSEvents watcher for the three folders. — `FolderWatcher.swift`
- [x] 2.2 CloudKit sync: upload/update, evict over-budget, remove deleted. —
  `RemoteFilesController.reconcile()`, `CloudKitRemoteFileStore`
- [x] 2.3 Thumbnail generation for supported types. — `QLThumbnailGenerator` in
  `RemoteFilesController` (commit 391975f "real thumbnails").
- [x] 2.4 Settings master toggle (off ⇒ purge cache) + ignore-list UI for
  subfolders (added on `fix/audit-findings`). *(Budget-config UI and explicit
  quota-full surfacing remain follow-ups.)*

## 3. Phone Files browser (Apps/FipleiOS) — code done; entitlements pending (0.3)

- [x] 3.1 List by folder + Favorites section; filename search; UTI icons. — `FilesView.swift`
- [x] 3.2 Download → Quick Look (share via the Quick Look share action), with a
  determinate progress ring (commit 0872540 "real download progress") and a
  failure alert.
- [x] 3.3 Pin/unpin (`isPinned`) with favorites-limit alert.
- [x] 3.4 Sync status (last-updated) + unavailable states (iCloud off /
  feature off). — `RemoteFilesStore.State`

## 4. Governance & privacy

- [x] 4.1 App Store data-use / privacy-manifest disclosure for the CloudKit
  store. — `Apps/*/PrivacyInfo.xcprivacy` + `docs/release/app-review-notes.md`
  (commit 79c7cdd "App Store prep").
- [ ] 4.2 Update `docs/architecture/` from implementation evidence after ship.

## 5. Verification Evidence

| Check | Command / Method | Result |
| --- | --- | --- |
| Budget admission + oldest-first eviction (age/count/size) | `swift test` (CachePlannerTests) | ✅ Pass |
| Pinned pool exempt from eviction; separate quota; limit refuses | `swift test` (CachePlannerTests/RemoteFileCacheTests) | ✅ Pass |
| Stable `recordName` — re-upload updates, no duplicate | `swift test` (RemoteFileTests) | ✅ Pass |
| Exclusion filter (hidden/system/bundles/ignore list) | `swift test` (FileExclusionTests) | ✅ Pass |
| Read-only invariant — deletion hits CloudKit only, never reads disk | `swift test` (RemoteFileCacheTests) + `FileReading` has no mutators | ✅ Pass |
| Loopback upload → list → download over in-memory store | `swift test` (RemoteFileCacheTests) | ✅ Pass |
| Full FipleKit suite | `cd FipleKit && swift test` | ✅ 75/75, 17 suites |
| Both apps build | `xcodebuild -scheme FipleMac` / `-scheme FipleiOS` | ✅ BUILD SUCCEEDED |
| Download on a different network; download with Mac off | Manual on-device | ⏳ Pending 0.3 provisioning |
| Apple ID mismatch / iCloud off shows guidance | Manual on-device | ⏳ Pending 0.3 provisioning |

## 6. Post-acceptance (governance close-out)

- [ ] 6.1 Human sets ADR-0004 and PRD to `accepted`.
- [ ] 6.2 Promote spec delta into `openspec/specs/remote-file-access/`.
- [ ] 6.3 Archive to `openspec/changes/archive/YYYY-MM-DD-add-remote-file-access/`.
