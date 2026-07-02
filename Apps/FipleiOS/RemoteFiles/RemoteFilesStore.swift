import CloudKit
import FipleKit
import Foundation
import Observation

/// iPhone side of off-LAN file access: lists the Mac's cached files from the
/// private CloudKit database, downloads them, and pins/unpins favorites.
///
/// Independent of the LAN `RemoteController` — this works over any network via
/// iCloud, which is the whole point (the Mac may be asleep at home). The
/// CloudKit store is created lazily so an install without the iCloud entitlement
/// never constructs a `CKContainer` until the user opens Files.
@MainActor
@Observable
final class RemoteFilesStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        /// iCloud not available / different Apple ID.
        case unavailable(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var files: [RemoteFile] = []
    private(set) var downloading: Set<String> = []
    /// When the newest cached file was last modified — a proxy for "last synced",
    /// shown so the user knows how fresh the list is.
    var lastModified: Date? { files.map(\.modifiedAt).max() }

    @ObservationIgnored private var backing: CloudKitRemoteFileStore?
    @ObservationIgnored private var cache: RemoteFileCache?

    /// Files grouped for display: pinned first, then by folder, newest first.
    var pinned: [RemoteFile] { files.filter(\.isPinned).sorted { $0.modifiedAt > $1.modifiedAt } }

    func files(in folder: SourceFolder) -> [RemoteFile] {
        files.filter { !$0.isPinned && $0.sourceFolder == folder }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Builds the CloudKit-backed store once iCloud is confirmed available.
    ///
    /// Availability is checked with `CKContainer.accountStatus()` — the correct
    /// signal for CloudKit — not `ubiquityIdentityToken`, which is about iCloud
    /// Drive and is unreliable (often nil in the Simulator even when signed in).
    private func ensureStore() async -> (CloudKitRemoteFileStore, RemoteFileCache)? {
        if let backing, let cache { return (backing, cache) }
        let container = CKContainer(identifier: RemoteFilesConfig.containerID)
        guard (try? await container.accountStatus()) == .available else { return nil }
        let store = CloudKitRemoteFileStore(containerIdentifier: RemoteFilesConfig.containerID)
        let cache = RemoteFileCache(store: store, reader: DiskFileReader(), deviceID: "phone")
        backing = store
        self.cache = cache
        return (store, cache)
    }

    func refresh() async {
        guard let (store, _) = await ensureStore() else {
            state = .unavailable("Sign in to the same Apple ID with iCloud on this iPhone and your Mac to see your files.")
            return
        }
        if files.isEmpty { state = .loading }
        do {
            files = try await store.list()
            state = .loaded
        } catch {
            state = .failed("Couldn't reach iCloud. Pull to try again.")
        }
    }

    /// Download a file's contents to a local URL for Quick Look / sharing.
    func download(_ file: RemoteFile) async -> URL? {
        guard let (store, _) = await ensureStore() else { return nil }
        downloading.insert(file.recordName)
        defer { downloading.remove(file.recordName) }
        do {
            let data = try await store.download(recordName: file.recordName)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FipleDownloads", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(file.fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Returns false if the favorites budget is full.
    @discardableResult
    func setPinned(_ file: RemoteFile, _ pinned: Bool) async -> Bool {
        guard let (_, cache) = await ensureStore() else { return false }
        let ok: Bool
        if pinned {
            ok = (try? await cache.pin(recordName: file.recordName)) ?? false
        } else {
            try? await cache.unpin(recordName: file.recordName)
            ok = true
        }
        if ok { await refresh() }
        return ok
    }
}

/// Shared config for the CloudKit container id (matches the app bundle id).
enum RemoteFilesConfig {
    static let containerID = "iCloud.com.maksatov.fipleapp"
}
