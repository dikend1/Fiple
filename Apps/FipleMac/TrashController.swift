import AppKit
import FipleKit
import Observation
import QuickLookThumbnailing
import UserNotifications

/// Owns the Mac side of Smart Trash: the granted folders (security-scoped
/// bookmarks), the daily staleness scan, deadline enforcement, local
/// notifications, and QuickLook thumbnails for the phone's review grid.
/// Off by default; disabling clears pending candidates (the keep-list survives).
@MainActor
@Observable
final class TrashController {
    private(set) var enabled: Bool
    private(set) var thresholdDays: Int
    /// Resolved, currently-accessible granted folders (for the Settings list).
    private(set) var folders: [URL] = []
    private(set) var candidates: [TrashCandidate] = []

    /// Notifies when the candidate list changes, so the server re-pushes it.
    @ObservationIgnored var didChange: (() -> Void)?

    @ObservationIgnored private let store: TrashCandidateStore
    @ObservationIgnored private let enforcer = TrashDeadlineEnforcer()
    @ObservationIgnored private var scanTimer: Timer?
    @ObservationIgnored private var thumbnailCache: [UUID: Data] = [:]
    /// Whether we've already asked for notification permission this launch.
    @ObservationIgnored private var requestedNotificationAuth = false

    private static let enabledKey = "fiple.trash.enabled"
    private static let thresholdKey = "fiple.trash.thresholdDays"
    private static let bookmarksKey = "fiple.trash.bookmarks"
    private static let reviewWindow: TimeInterval = 7 * 86_400

    private var scanner: StaleFileScanner {
        StaleFileScanner(
            stalenessThreshold: TimeInterval(thresholdDays) * 86_400,
            reviewWindow: Self.reviewWindow
        )
    }

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let days = UserDefaults.standard.integer(forKey: Self.thresholdKey)
        thresholdDays = [30, 60, 90].contains(days) ? days : 60

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fiple", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        store = TrashCandidateStore(fileURL: support.appendingPathComponent("trash.json"))

        folders = Self.resolveBookmarks()
        candidates = store.candidates
        if enabled {
            // Catch up on deadlines missed while the Mac was asleep or off,
            // then start the daily cadence.
            enforceAndNotify()
            scheduleDailyScan()
            scanNow()
        }
    }

    // MARK: - Settings surface

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            requestNotificationAuthOnce()
            enforceAndNotify()
            scheduleDailyScan()
            scanNow()
        } else {
            scanTimer?.invalidate()
            scanTimer = nil
            store.clearCandidates()
            thumbnailCache.removeAll()
            refresh()
        }
    }

    func setThresholdDays(_ days: Int) {
        thresholdDays = days
        UserDefaults.standard.set(days, forKey: Self.thresholdKey)
        if enabled { scanNow() }
    }

    /// Presents the folder grant panel and stores a security-scoped bookmark.
    func grantFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = "Grant Access"
        panel.message = "Choose folders Fiple may scan for stale files (e.g. Downloads, Desktop)."
        guard panel.runModal() == .OK else { return }

        var bookmarks = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        for url in panel.urls where !folders.contains(url) {
            if let bookmark = try? url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
            ) {
                bookmarks.append(bookmark)
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
        folders = Self.resolveBookmarks()
        if enabled { scanNow() }
    }

    func removeFolder(_ url: URL) {
        let bookmarks = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        let remaining = bookmarks.filter { data in
            var stale = false
            let resolved = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &stale
            )
            return resolved != url
        }
        UserDefaults.standard.set(remaining, forKey: Self.bookmarksKey)
        folders = Self.resolveBookmarks()
        // Candidates under the revoked folder are no longer scannable — drop them.
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        let dropped = store.candidates.filter { $0.path.hasPrefix(prefix) }.map(\.id)
        if !dropped.isEmpty { store.remove(ids: Set(dropped)) }
        refresh()
    }

    // MARK: - Scan & enforcement

    func scanNow() {
        guard enabled else { return }
        let now = Date()
        scanner.scan(folders: folders, store: store, now: now)
        refresh()
        notifyUpcomingDeadlines(now: now)
    }

    private func scheduleDailyScan() {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.enforceAndNotify()
                self.scanNow()
            }
        }
    }

    private func enforceAndNotify() {
        let trashed = enforcer.enforce(store: store, scanner: scanner, now: Date())
        refresh()
        guard !trashed.isEmpty else { return }
        let body = trashed.count == 1
            ? "“\(trashed[0].fileName)” was moved to the Trash after its review window expired."
            : "\(trashed.count) unreviewed files were moved to the Trash. They're recoverable from the macOS Trash."
        postNotification(id: "fiple.trash.autotrashed", title: "Smart Trash", body: body)
    }

    /// One reminder when any candidate is within 2 days of its deadline.
    private func notifyUpcomingDeadlines(now: Date) {
        let soon = candidates.filter { $0.deadline.timeIntervalSince(now) <= 2 * 86_400 }
        guard !soon.isEmpty else { return }
        let body = soon.count == 1
            ? "“\(soon[0].fileName)” moves to the Trash soon. Review it on your iPhone."
            : "\(soon.count) files move to the Trash soon. Review them on your iPhone."
        postNotification(id: "fiple.trash.reminder", title: "Smart Trash", body: body)
    }

    // MARK: - Phone review

    /// Applies a phone decision and returns the typed result message.
    func applyReview(ids: [UUID], decision: TrashDecision) -> ServerMessage {
        let result = TrashReviewHandler().apply(
            ids: ids, decision: decision, store: store, scanner: scanner, now: Date()
        )
        thumbnailCache = thumbnailCache.filter { key, _ in store.candidate(id: key) != nil }
        refresh()
        return result
    }

    /// QuickLook thumbnail (JPEG) for one candidate, cached per id.
    func thumbnail(for id: UUID) async -> Data? {
        if let cached = thumbnailCache[id] { return cached }
        guard let candidate = store.candidate(id: id) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: candidate.path),
            size: CGSize(width: 240, height: 240), scale: 2, representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
              let tiff = rep.nsImage.tiffRepresentation,
              let jpeg = NSBitmapImageRep(data: tiff)?
                  .representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return nil }
        thumbnailCache[id] = jpeg
        return jpeg
    }

    // MARK: - Helpers

    private func refresh() {
        candidates = store.candidates
        didChange?()
    }

    private func requestNotificationAuthOnce() {
        guard !requestedNotificationAuth else { return }
        requestedNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    private func postNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }

    /// Resolves stored bookmarks and starts security-scoped access for each.
    private static func resolveBookmarks() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        var urls: [URL] = []
        for data in bookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &stale
            ) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            if !urls.contains(url) { urls.append(url) }
        }
        return urls
    }
}
