import AppKit
import CloudKit
import FipleKit
import Foundation
import Observation
import QuickLookThumbnailing

/// Drives the Mac side of off-LAN file access: owns the on/off toggle, the
/// folder watcher, and the read-only mirror into the private CloudKit cache.
///
/// The CloudKit store is created **lazily**, only when the feature is enabled, so
/// an install without the iCloud entitlement/container provisioned never
/// constructs a `CKContainer` at launch. Everything it does to disk is read-only
/// (via `DiskFileReader`); deletion touches only the cloud cache.
@MainActor
@Observable
final class RemoteFilesController {
    /// CloudKit container id — matches the app bundle id. Provisioned by the
    /// developer (gate 0.3 in the OpenSpec change) before this can reach iCloud.
    static let containerID = "iCloud.com.maksatov.fipleapp"

    private(set) var isEnabled: Bool
    /// Human-readable last state for the Settings UI.
    private(set) var status: String = "Off"
    /// Subfolder names (relative to a watched folder) the user excluded from
    /// mirroring, e.g. `Private` or `Work/Secret`. Persisted; edited in Settings.
    private(set) var ignoredSubfolders: [String]

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let enabledKey = "remoteFiles.enabled"
    @ObservationIgnored private let deviceIDKey = "remoteFiles.deviceID"
    @ObservationIgnored private let ignoredSubfoldersKey = "remoteFiles.ignoredSubfolders"

    @ObservationIgnored private let reader = DiskFileReader()
    @ObservationIgnored private var store: CloudKitRemoteFileStore?
    @ObservationIgnored private var cache: RemoteFileCache?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var reconciling = false
    @ObservationIgnored private let deviceID: String

    init() {
        // Hard-off when the feature flag is disabled (1.0 LAN-only release), even
        // if a prior build persisted an enabled state — with the iCloud
        // entitlement removed there is nothing to sync to.
        isEnabled = AppFeatures.remoteFiles && defaults.bool(forKey: enabledKey)
        ignoredSubfolders = defaults.stringArray(forKey: ignoredSubfoldersKey) ?? []
        if let saved = defaults.string(forKey: deviceIDKey) {
            deviceID = saved
        } else {
            let new = UUID().uuidString
            defaults.set(new, forKey: deviceIDKey)
            deviceID = new
        }
        if isEnabled { start() }
    }

    /// Standard folders we mirror. Missing ones are skipped.
    ///
    /// Uses the *real* home directory, not `FileManager.urls(for:in:)`, which a
    /// sandboxed app redirects to its container (`…/Containers/…/Data/Desktop`,
    /// which is empty). `getpwuid` returns the true `/Users/<me>` path; the
    /// home-relative-path read-only entitlement grants access there.
    private var watchedFolders: [(SourceFolder, URL)] {
        let home = Self.realHomeDirectory
        let fm = FileManager.default
        let candidates: [(SourceFolder, URL)] = [
            (.desktop, home.appendingPathComponent("Desktop", isDirectory: true)),
            (.documents, home.appendingPathComponent("Documents", isDirectory: true)),
            (.downloads, home.appendingPathComponent("Downloads", isDirectory: true)),
        ]
        return candidates.filter { fm.fileExists(atPath: $0.1.path) }
    }

    /// Generate a small JPEG preview for a file via Quick Look, uploaded as the
    /// thumbnail so the phone shows a real image instead of a generic glyph.
    /// Returns nil for types Quick Look can't render (falls back to a glyph).
    @Sendable private static func makeThumbnail(for url: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 240, height: 240),
            scale: 2,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: rep.cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }

    /// The user's real home directory, bypassing sandbox container redirection.
    private static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        defaults.set(on, forKey: enabledKey)
        if on { start() } else { stopAndPurge() }
    }

    private func start() {
        // iCloud must be signed in; otherwise stay off and tell the user why.
        guard FileManager.default.ubiquityIdentityToken != nil else {
            FipleLog.remoteFiles.error("start aborted — no iCloud account signed in on this Mac")
            status = "Sign in to iCloud on this Mac to enable remote file access."
            return
        }
        FipleLog.remoteFiles.info("start — iCloud available, container \(Self.containerID)")
        let store = CloudKitRemoteFileStore(containerIdentifier: Self.containerID)
        self.store = store
        cache = makeCache(store: store)

        watcher = FolderWatcher(urls: watchedFolders.map(\.1)) { [weak self] in
            Task { @MainActor in self?.reconcile() }
        }
        watcher?.start()
        status = "On — syncing recent files"
        reconcile()
    }

    /// The exclusion list is baked into the cache at construction, so both
    /// `start()` and ignore-list edits build it through this one place.
    private func makeCache(store: CloudKitRemoteFileStore) -> RemoteFileCache {
        RemoteFileCache(
            store: store,
            reader: reader,
            deviceID: deviceID,
            ignoredSubfolders: ignoredSubfolders,
            thumbnailProvider: Self.makeThumbnail
        )
    }

    /// Add a user-ignored subfolder (name relative to a watched folder).
    /// Duplicates (case-insensitive) and empty input are dropped silently.
    func addIgnoredSubfolder(_ name: String) {
        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              !ignoredSubfolders.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        ignoredSubfolders.append(trimmed)
        persistIgnoredSubfoldersAndReconcile()
    }

    func removeIgnoredSubfolder(_ name: String) {
        ignoredSubfolders.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        persistIgnoredSubfoldersAndReconcile()
    }

    private func persistIgnoredSubfoldersAndReconcile() {
        defaults.set(ignoredSubfolders, forKey: ignoredSubfoldersKey)
        guard let store else { return } // feature off — applies on next start()
        // Rebuild the cache so the new list takes effect, then reconcile: files
        // in newly-ignored subfolders come back .excluded and their cloud copies
        // are dropped as stale.
        cache = makeCache(store: store)
        reconcile()
    }

    private func stopAndPurge() {
        watcher?.stop()
        watcher = nil
        let cache = self.cache
        self.cache = nil
        self.store = nil
        status = "Off"
        // Best-effort purge of the cloud cache (never touches disk originals).
        Task { try? await cache?.disableAndPurge() }
    }

    /// Enumerate the watched folders and reconcile the cache: upload new/changed
    /// files, evict per budget, and drop cache copies for files removed on disk.
    func reconcile() {
        guard let cache, let store, !reconciling else { return }
        reconciling = true
        let folders = watchedFolders
        let deviceID = self.deviceID

        Task {
            defer { reconciling = false }
            let now = Date()
            var liveRecordNames: Set<String> = []
            var scanned = 0, cached = 0, unchanged = 0, skipped = 0, excluded = 0, failed = 0

            FipleLog.remoteFiles.info("reconcile start — \(folders.count) folder(s): \(folders.map { $0.1.lastPathComponent }.joined(separator: ", "))")

            // One CloudKit listing per reconcile: handleChange keeps this
            // snapshot in sync with its own uploads/evictions, so scanning N
            // files no longer costs N full queries (which tripped CloudKit's
            // rate limits on every FSEvent).
            var snapshot: [RemoteFile]
            do {
                snapshot = try await store.list()
            } catch {
                FipleLog.remoteFiles.error("reconcile aborted — listing the cache failed: \(error)")
                return
            }

            var quotaHit = false
            outer: for (folder, root) in folders {
                let files = Self.files(in: root)
                FipleLog.remoteFiles.info("scanning \(folder.rawValue): \(files.count) file(s) under \(root.path)")
                for (url, relativePath) in files {
                    scanned += 1
                    let recordName = RemoteFile.recordName(deviceID: deviceID, folder: folder, relativePath: relativePath)
                    liveRecordNames.insert(recordName)
                    do {
                        switch try await cache.handleChange(at: url, folder: folder, relativePath: relativePath, snapshot: &snapshot, now: now) {
                        case .cached: cached += 1
                        case .unchanged: unchanged += 1
                        case .skipped: skipped += 1
                        case .excluded:
                            // Not live: if the user just ignored this subfolder,
                            // its existing cloud copy becomes stale below.
                            excluded += 1
                            liveRecordNames.remove(recordName)
                        }
                    } catch let error as CKError where error.code == .quotaExceeded {
                        // The user's iCloud storage is full. Stop hammering (which
                        // trips CloudKit's error-rate mitigation) and tell them.
                        quotaHit = true
                        FipleLog.remoteFiles.error("iCloud quota exceeded — pausing sync")
                        status = "iCloud storage full — free up space to sync files."
                        break outer
                    } catch {
                        failed += 1
                        FipleLog.remoteFiles.error("upload failed for \(relativePath): \(error)")
                    }
                }
            }

            FipleLog.remoteFiles.info("reconcile done — scanned \(scanned), cached \(cached), unchanged \(unchanged), skipped \(skipped), excluded \(excluded), failed \(failed)\(quotaHit ? " (paused: iCloud full)" : "")")
            if !quotaHit, cached + unchanged > 0 { status = "On — \(cached + unchanged) file(s) synced" }
            if quotaHit { return }

            // Deletions: our device's cache copies whose originals are gone (or
            // just became excluded). The maintained snapshot already reflects
            // this reconcile's uploads, so no second listing is needed.
            let stale = snapshot
                .filter { $0.sourceDeviceID == deviceID && !liveRecordNames.contains($0.recordName) }
                .map(\.recordName)
            if !stale.isEmpty {
                do {
                    try await store.delete(recordNames: stale)
                    FipleLog.remoteFiles.info("evicted \(stale.count) stale cache copies")
                } catch {
                    FipleLog.remoteFiles.error("stale delete failed: \(error)")
                }
            }
        }
    }

    /// Shallow-to-deep enumeration returning (fileURL, relativePath) for regular
    /// files under `root`, skipping hidden entries and directories.
    private static func files(in root: URL) -> [(URL, String)] {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var out: [(URL, String)] = []
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let url as URL in en {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile else { continue }
            let relativePath = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent
            out.append((url, relativePath))
        }
        return out
    }
}
