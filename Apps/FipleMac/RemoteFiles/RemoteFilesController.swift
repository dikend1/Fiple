import FipleKit
import Foundation
import Observation

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

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let enabledKey = "remoteFiles.enabled"
    @ObservationIgnored private let deviceIDKey = "remoteFiles.deviceID"

    @ObservationIgnored private let reader = DiskFileReader()
    @ObservationIgnored private var store: CloudKitRemoteFileStore?
    @ObservationIgnored private var cache: RemoteFileCache?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var reconciling = false
    @ObservationIgnored private let deviceID: String

    init() {
        isEnabled = defaults.bool(forKey: enabledKey)
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
        cache = RemoteFileCache(store: store, reader: reader, deviceID: deviceID)

        watcher = FolderWatcher(urls: watchedFolders.map(\.1)) { [weak self] in
            Task { @MainActor in self?.reconcile() }
        }
        watcher?.start()
        status = "On — syncing recent files"
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
            var scanned = 0, cached = 0, skipped = 0, excluded = 0, failed = 0

            FipleLog.remoteFiles.info("reconcile start — \(folders.count) folder(s): \(folders.map { $0.1.lastPathComponent }.joined(separator: ", "))")

            for (folder, root) in folders {
                let files = Self.files(in: root)
                FipleLog.remoteFiles.info("scanning \(folder.rawValue): \(files.count) file(s) under \(root.path)")
                for (url, relativePath) in files {
                    scanned += 1
                    liveRecordNames.insert(
                        RemoteFile.recordName(deviceID: deviceID, folder: folder, relativePath: relativePath)
                    )
                    do {
                        switch try await cache.handleChange(at: url, folder: folder, relativePath: relativePath, now: now) {
                        case .cached: cached += 1
                        case .skipped: skipped += 1
                        case .excluded: excluded += 1
                        }
                    } catch {
                        failed += 1
                        FipleLog.remoteFiles.error("upload failed for \(relativePath): \(error)")
                    }
                }
            }

            FipleLog.remoteFiles.info("reconcile done — scanned \(scanned), cached \(cached), skipped \(skipped), excluded \(excluded), failed \(failed)")

            // Deletions: our device's cache copies whose originals are gone.
            do {
                let existing = try await store.list()
                let stale = existing
                    .filter { $0.sourceDeviceID == deviceID && !liveRecordNames.contains($0.recordName) }
                    .map(\.recordName)
                if !stale.isEmpty {
                    try await store.delete(recordNames: stale)
                    FipleLog.remoteFiles.info("evicted \(stale.count) stale cache copies")
                }
            } catch {
                FipleLog.remoteFiles.error("list/delete failed: \(error)")
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
