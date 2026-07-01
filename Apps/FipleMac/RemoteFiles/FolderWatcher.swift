import Foundation

/// Watches a set of folders recursively via FSEvents and fires a debounced
/// callback whenever anything under them changes.
///
/// Deliberately coarse: it reports "something changed," and the caller responds
/// with a full rescan-and-reconcile of the watched folders. That is simpler and
/// more robust than decoding per-event flags, and the rescan cost is bounded by
/// the small standard-folder set.
final class FolderWatcher {
    private let paths: [String]
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.maksatov.fiple.folderwatcher")
    private var stream: FSEventStreamRef?

    /// - Parameters:
    ///   - urls: folders to watch recursively.
    ///   - onChange: invoked (already debounced by FSEvents' latency) on changes.
    init(urls: [URL], onChange: @escaping @Sendable () -> Void) {
        self.paths = urls.map(\.path)
        self.onChange = onChange
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1s latency → natural debounce
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
