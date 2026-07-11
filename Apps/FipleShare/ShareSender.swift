import FipleKit
import Foundation
import Network
import UniformTypeIdentifiers

/// The extension's whole job as a state machine: resolve the shared item,
/// find the paired Mac on the LAN, authenticate with the stored token, send.
///
/// Runs its own discovery + connection because the extension is a separate
/// process — it cannot borrow the main app's live socket. Small and sequential
/// on purpose: one item, one Mac, one transfer.
@MainActor
@Observable
final class ShareSender {
    enum Phase: Equatable {
        case resolving          // reading the shared item from the provider
        case searching          // browsing for the paired Mac
        case sending(Double)    // beaming (progress 0…1)
        case doneFile(String)   // landed in Downloads (file name)
        case doneClipboard      // text/URL is on the Mac's clipboard
        case failed(String)
    }

    private(set) var phase: Phase = .resolving
    /// What we're sending, for the card's subtitle ("IMG_1234.heic" / a URL).
    private(set) var itemLabel = ""

    /// The same key the main app stores its reconnect token under.
    private static let tokenKey = "fiple.token"
    // 4 MB raw → ~5.4 MB once base64'd into the JSON frame, under the 8 MB
    // frame cap; matches the main app's beam chunk size.
    private static let chunkSize = 4 * 1024 * 1024

    private enum Payload {
        case file(URL)
        case text(String)
    }

    func run(attachments: [NSItemProvider]) async {
        guard let token = Keychain.get(Self.tokenKey) else {
            phase = .failed("Open Fiple once and pair with your Mac first.")
            return
        }
        guard let payload = await resolve(attachments) else {
            phase = .failed("This item can't be sent.")
            return
        }

        phase = .searching
        guard let peer = await connectToPairedMac(token: token) else {
            phase = .failed("Couldn't find your Mac. Make sure it's awake and on the same Wi-Fi.")
            return
        }
        defer { Task { await peer.close() } }

        switch payload {
        case let .text(text):
            do {
                try await peer.send(ClientMessage.setClipboard(text: text))
                phase = .doneClipboard
            } catch {
                phase = .failed("Couldn't reach your Mac — nothing was sent.")
            }
        case let .file(url):
            await beam(url, over: peer)
        }
    }

    // MARK: - Item resolution

    private func resolve(_ attachments: [NSItemProvider]) async -> Payload? {
        // Prefer a concrete file (photo, video, document); fall back to URL/text.
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
            if let url = await loadFile(from: provider) {
                itemLabel = url.lastPathComponent
                return .file(url)
            }
        }
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let text = await loadText(from: provider, type: UTType.url) {
                itemLabel = text
                return .text(text)
            }
        }
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadText(from: provider, type: UTType.plainText) {
                itemLabel = text
                return .text(text)
            }
        }
        return nil
    }

    private func loadText(from provider: NSItemProvider, type: UTType) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: url.absoluteString)
                case let text as String: continuation.resume(returning: text)
                case let data as Data: continuation.resume(returning: String(data: data, encoding: .utf8))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Copies the provider's file representation into our container (the
    /// provider deletes its temp URL when the completion handler returns).
    private func loadFile(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.createDirectory(
                    at: copy.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Find + authenticate

    /// Browses the LAN and tries the stored token against each discovered Mac
    /// until one accepts (several Macs may advertise; only ours knows the
    /// token). Bounded by an overall deadline so the card never spins forever.
    private func connectToPairedMac(token: String) async -> PeerConnection? {
        let client = FipleClient()
        let deadline = Date().addingTimeInterval(10)

        for await endpoint in await client.discover() {
            if Date() > deadline { break }
            guard let peer = try? await client.connect(to: endpoint, timeout: .seconds(4)) else { continue }
            do {
                // Guest auth: never claims the main peer slot, so the app's own
                // live connection isn't evicted (it would instantly reconnect
                // and kill this transfer).
                try await peer.send(ClientMessage.guestReconnect(token: token))
            } catch {
                await peer.close()
                continue
            }
            // First relevant reply decides: paired → ours; rejected → try next.
            let accepted = await withDeadline(seconds: 5) {
                do {
                    for try await payload in await peer.messages {
                        guard let message = try? MessageCodec.decodeIfKnown(ServerMessage.self, from: payload)
                        else { continue }
                        if case .paired = message { return true }
                        if case .pairRejected = message { return false }
                    }
                } catch {}
                return false
            } ?? false
            if accepted { return peer }
            await peer.close()
        }
        return nil
    }

    // MARK: - Beam

    private func beam(_ url: URL, over peer: PeerConnection) async {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        guard let totalBytes = size, totalBytes > 0 else {
            phase = .failed("Couldn't read the shared file.")
            return
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            phase = .failed("Couldn't read the shared file.")
            return
        }
        defer { try? handle.close() }

        let transferID = UUID()
        phase = .sending(0)
        do {
            try await peer.send(ClientMessage.beamBegin(
                transferID: transferID, name: url.lastPathComponent, totalBytes: totalBytes
            ))
            var sent: Int64 = 0
            while sent < totalBytes {
                guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
                // Raw binary frame — no base64/JSON on the hot path.
                try await peer.sendRaw(BeamBinary.encodeChunk(transferID: transferID, bytes: chunk))
                sent += Int64(chunk.count)
                phase = .sending(Double(sent) / Double(totalBytes))
            }
            try await peer.send(ClientMessage.beamEnd(transferID: transferID))
        } catch {
            phase = .failed("The connection dropped mid-transfer.")
            return
        }

        // Wait for the Mac's typed result.
        let result: ShareSender.Phase? = await withDeadline(seconds: 15) {
            do {
                for try await payload in await peer.messages {
                    guard let message = try? MessageCodec.decodeIfKnown(ServerMessage.self, from: payload),
                          case let .beamResult(id, ok, note) = message, id == transferID else { continue }
                    return ok
                        ? .doneFile(note ?? url.lastPathComponent)
                        : .failed(note ?? "The Mac couldn't save the file.")
                }
            } catch {}
            return nil
        } ?? nil
        phase = result ?? .failed("The Mac didn't confirm the transfer.")
    }
}

/// Races `work` against a deadline; nil when the deadline wins. Keeps the
/// share card from ever hanging on a silent peer.
private func withDeadline<T: Sendable>(
    seconds: TimeInterval, _ work: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await work() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
