# Tasks — Add off-LAN remote file access

> New work, **not started**. Blocked on human acceptance of ADR-0004 and PRD
> `fiple-remote-file-access.md`. Do not implement until accepted. Complete tasks
> sequentially and record verification evidence before marking a task done.

## 0. Gate (must clear before any implementation)

- [ ] 0.1 Human accepts ADR-0004 (off-LAN via CloudKit).
- [ ] 0.2 Human accepts PRD `fiple-remote-file-access.md`.
- [ ] 0.3 CloudKit container + iCloud entitlement provisioned in the Apple
  Developer account and added to `project.yml` for both apps.

## 1. Core model & budget (FipleKit)

- [ ] 1.1 `RemoteFile` record model (fields per design) with stable `recordName`
  derivation (`sourceDeviceID + sourceFolder + relativePath`).
- [ ] 1.2 Budget engine: admission + oldest-first eviction for the fresh pool
  (age/count/size) and a separate pinned pool (count/size), with per-file cap.
- [ ] 1.3 Exclusion filter (hidden/system, `.app`/`.dmg`, package dirs, user
  ignore list).
- [ ] 1.4 Read-only file reader interface (no mutating operations) + guard that
  eviction targets CloudKit only.

## 2. Mac agent (Apps/FipleMac)

- [ ] 2.1 FSEvents watcher for Desktop / Documents / Downloads → change queue.
- [ ] 2.2 CloudKit sync: upload/update `RemoteFile` (payload + thumbnail),
  evict over-budget copies, remove copies for files deleted from disk.
- [ ] 2.3 Thumbnail generation for supported types.
- [ ] 2.4 Settings: master toggle (off ⇒ purge cache), budget config, ignore
  list. iCloud-quota-full surfaced, uploads paused, originals untouched.

## 3. Phone Files browser (Apps/FipleiOS)

- [ ] 3.1 Fetch `RemoteFile` records; list by folder + Favorites section;
  filename search; type icons/previews.
- [ ] 3.2 Download `payload` with progress → Open (Quick Look) / Share sheet.
- [ ] 3.3 Pin/unpin (sets `isPinned`); favorites-limit message.
- [ ] 3.4 Sync status (last refresh + offline indicator) and unavailable states
  (feature off; Apple ID mismatch / iCloud off).

## 4. Governance & privacy

- [ ] 4.1 App Store data-use / privacy-manifest disclosure for the CloudKit
  store.
- [ ] 4.2 Update `docs/architecture/` from implementation evidence after ship.

## 5. Verification Evidence

| Check | Command / Method | Result |
| --- | --- | --- |
| Budget admission + oldest-first eviction (age/count/size) | `swift test` (BudgetTests) | ⏳ |
| Pinned pool exempt from eviction; separate quota; limit refuses | `swift test` (PinTests) | ⏳ |
| Stable `recordName` — re-upload updates, no duplicate | `swift test` (RecordNameTests) | ⏳ |
| Exclusion filter (hidden/system/bundles/ignore list) | `swift test` (ExclusionTests) | ⏳ |
| Read-only invariant — no disk-mutating path; eviction hits CloudKit only | `swift test` + code review | ⏳ |
| Loopback upload → list → download over mocked CloudKit | `swift test` (RemoteFileLoopbackTests) | ⏳ |
| Both apps build | `xcodebuild -scheme FipleMac` / `-scheme FipleiOS` | ⏳ |
| Download on a different network; download with Mac off | Manual on-device | ⏳ |
| Apple ID mismatch / iCloud off shows guidance | Manual on-device | ⏳ |

## 6. Post-acceptance (governance close-out)

- [ ] 6.1 Human sets ADR-0004 and PRD to `accepted`.
- [ ] 6.2 Promote spec delta into `openspec/specs/remote-file-access/`.
- [ ] 6.3 Archive to `openspec/changes/archive/YYYY-MM-DD-add-remote-file-access/`.
