#if os(macOS)
import Foundation

/// Assembles a chunked file beamed from the phone and lands it in the
/// destination folder (~/Downloads in the app; injected for tests).
///
/// Chunks stream to a temp file — never held in RAM — so a large video can't
/// balloon the process. One transfer at a time: a new `begin` discards any
/// unfinished predecessor, and `abort()` (peer dropped) cleans up. File names
/// are sanitized and collisions get " (2)"-style suffixes, so the phone can
/// never write outside the folder or overwrite an existing file.
public final class BeamReceiver: @unchecked Sendable {
    public static let maxBytes: Int64 = 500 * 1024 * 1024

    private struct Transfer {
        let id: UUID
        let name: String
        let totalBytes: Int64
        let tempURL: URL
        let handle: FileHandle
        var received: Int64 = 0
    }

    private let destination: URL
    private var current: Transfer?

    public init(destination: URL) {
        self.destination = destination
    }

    public enum Outcome: Equatable {
        case accepted
        /// Transfer finished; the file landed at `fileName` in the destination.
        case completed(fileName: String)
        case failed(String)
    }

    /// Starts a transfer, discarding any unfinished one (the phone gave up on
    /// it — only one runs at a time).
    public func begin(id: UUID, name: String, totalBytes: Int64) -> Outcome {
        discardCurrent()
        guard totalBytes > 0, totalBytes <= Self.maxBytes else {
            return .failed("File is too large to send (limit \(Self.maxBytes / (1024 * 1024)) MB).")
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fiple-beam-\(id.uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else {
            return .failed("Couldn't prepare the transfer on the Mac.")
        }
        current = Transfer(
            id: id, name: Self.sanitized(name), totalBytes: totalBytes,
            tempURL: tempURL, handle: handle
        )
        return .accepted
    }

    /// Appends one chunk. Chunks for an unknown/superseded transfer are ignored.
    public func chunk(id: UUID, bytes: Data) -> Outcome {
        guard var transfer = current, transfer.id == id else { return .failed("Unknown transfer.") }
        transfer.received += Int64(bytes.count)
        guard transfer.received <= transfer.totalBytes else {
            discardCurrent()
            return .failed("The transfer sent more data than announced.")
        }
        do {
            try transfer.handle.write(contentsOf: bytes)
        } catch {
            discardCurrent()
            return .failed("Couldn't write the file on the Mac (disk full?).")
        }
        current = transfer
        return .accepted
    }

    /// Finalizes the transfer into the destination folder.
    public func end(id: UUID) -> Outcome {
        guard let transfer = current, transfer.id == id else { return .failed("Unknown transfer.") }
        current = nil
        try? transfer.handle.close()
        guard transfer.received == transfer.totalBytes else {
            try? FileManager.default.removeItem(at: transfer.tempURL)
            return .failed("The transfer ended early — try sending again.")
        }
        let target = Self.availableURL(for: transfer.name, in: destination)
        do {
            try FileManager.default.moveItem(at: transfer.tempURL, to: target)
        } catch {
            try? FileManager.default.removeItem(at: transfer.tempURL)
            return .failed("Couldn't save into the destination folder.")
        }
        return .completed(fileName: target.lastPathComponent)
    }

    /// Drops any unfinished transfer (peer disconnected).
    public func abort() {
        discardCurrent()
    }

    private func discardCurrent() {
        guard let transfer = current else { return }
        current = nil
        try? transfer.handle.close()
        try? FileManager.default.removeItem(at: transfer.tempURL)
    }

    /// Keeps just a safe file name: path separators and leading dots stripped,
    /// never empty.
    static func sanitized(_ name: String) -> String {
        var base = (name as NSString).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
        while base.hasPrefix(".") { base.removeFirst() }
        return base.isEmpty ? "Beamed file" : base
    }

    /// First non-colliding URL: "name.ext", "name (2).ext", "name (3).ext"…
    static func availableURL(for name: String, in folder: URL) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let next = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            let url = folder.appendingPathComponent(next)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }
}
#endif
