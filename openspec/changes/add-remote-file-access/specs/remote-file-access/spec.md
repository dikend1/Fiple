## ADDED Requirements

### Requirement: Off-LAN retrieval of recent files

The system SHALL let the phone retrieve files that originate on the Mac from any
network, including when the phone and Mac are not on the same Wi-Fi, using the
user's private CloudKit database as transport. Retrieval SHALL NOT require a Fiple
account or an in-app login.

#### Scenario: Download a file from a different network

- **WHEN** a file has been cached from the Mac and the phone is on a different
  network (e.g. cellular)
- **THEN** the phone lists the file and downloads its contents successfully
  without any same-Wi-Fi requirement

#### Scenario: Download while the Mac is asleep or off

- **WHEN** a file is already in the cache and the Mac is asleep or shut down
- **THEN** the phone can still download the file from iCloud

### Requirement: Bounded recent-files cache on the Mac

The Mac SHALL maintain a bounded cache of recent files from Desktop, Documents,
and Downloads in the private CloudKit database, admitting files that satisfy the
configured budget (default: modified within 30 days, ≤ 200 files, ≤ 2 GB total,
≤ 100 MB per file) and excluding hidden/system files, application/installer
bundles, and any user-ignored subfolder. When the budget is exceeded the Mac
SHALL evict cache copies oldest-first by last-modified time.

#### Scenario: Fresh file is added to the cache

- **WHEN** the user creates or modifies a file under a standard folder that fits
  the budget and is not excluded
- **THEN** the Mac uploads it to the private CloudKit database and it becomes
  visible on the phone

#### Scenario: Oldest cache copy is evicted over budget

- **WHEN** admitting a new file would exceed the count, size, or age budget
- **THEN** the Mac removes the oldest-by-last-modified cache copies from CloudKit
  until the budget is satisfied

#### Scenario: Oversized and excluded files are skipped

- **WHEN** a changed file exceeds the per-file size limit, or is a hidden/system
  file, an app/installer bundle, or under an ignored subfolder
- **THEN** the Mac does not upload it, and an oversized file is flagged rather
  than reported as an error

### Requirement: Read-only safety over the Mac filesystem

The system SHALL only read originals on the Mac filesystem to produce cache
copies. No feature path — eviction, disabling the feature, or an error — SHALL
delete or modify any file on the Mac disk. Deletion SHALL affect only cache
copies stored in CloudKit.

#### Scenario: Eviction never touches the original

- **WHEN** a cache copy is evicted because the budget is exceeded
- **THEN** only the CloudKit copy is removed and the original file on the Mac disk
  is unchanged

#### Scenario: Disabling the feature purges only the cache

- **WHEN** the user turns off the feature on the Mac
- **THEN** the entire CloudKit cache is purged and no original files on the Mac
  disk are deleted or modified

#### Scenario: The phone cannot mutate Mac files

- **WHEN** the user interacts with a file on the phone
- **THEN** the phone offers only browse, download, open, share, and pin/unpin —
  never edit, delete, move, or upload-back

### Requirement: Pinned favorites exempt from eviction

The system SHALL let the user pin a file from the phone so it is never evicted
while pinned, tracked in a separate favorites budget (default ≤ 50 files, ≤ 1 GB,
≤ 100 MB per file) that does not compete with the fresh-files pool. Unpinning
SHALL return the file to the normal budget.

#### Scenario: Pinned file survives eviction pressure

- **WHEN** the fresh-files budget is exceeded and a file is pinned
- **THEN** the pinned file is retained and only unpinned fresh files are eligible
  for eviction

#### Scenario: Pinning past the favorites limit is refused

- **WHEN** the user tries to pin a file beyond the favorites count or size limit
- **THEN** the pin is refused with a message to unpin something first

#### Scenario: Unpin returns a file to the normal budget

- **WHEN** the user unpins a file
- **THEN** the file is subject to the fresh-files budget again and may later be
  evicted

### Requirement: Apple ID based access with no in-app login

The system SHALL scope all cached data to the user's Apple ID via the private
CloudKit database, with no separate Fiple account. The Mac and phone SHALL
interoperate only when signed into the same Apple ID with iCloud enabled, and the
system SHALL clearly communicate when they are not.

#### Scenario: Same Apple ID interoperates without a code

- **WHEN** the Mac and phone are signed into the same Apple ID with iCloud enabled
- **THEN** the phone can browse and download cached files without entering a
  pairing code or credentials

#### Scenario: Mismatched Apple ID or iCloud off is explained

- **WHEN** the phone is on a different Apple ID, or iCloud is unavailable/disabled
- **THEN** the phone shows guidance to sign in to the same Apple ID with iCloud
  rather than an empty or broken screen

### Requirement: Files browser with honest sync status

The phone SHALL present cached files grouped by folder with a Favorites section,
support filename search, and allow downloading a file and then opening or sharing
it. It SHALL show when the cache was last refreshed and indicate when the Mac has
been offline.

#### Scenario: Browse, download, and share

- **WHEN** the user opens the Files section and taps a file
- **THEN** the file downloads with progress and can be opened in Quick Look or
  sent via the system share sheet

#### Scenario: Offline Mac is indicated

- **WHEN** the Mac has not refreshed the cache recently
- **THEN** the phone shows the last-refresh time and an offline indicator, while
  still allowing download of already-cached files

#### Scenario: Feature disabled on the Mac

- **WHEN** the feature is turned off on the Mac (cache purged)
- **THEN** the phone shows an empty state instructing the user to enable Remote
  file access on the Mac
