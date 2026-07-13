import Foundation

/// Messages sent from the iPhone remote to the Mac companion.
public enum ClientMessage: Sendable, Equatable {
    /// Attempt to pair using the code shown on the Mac (first-time pairing).
    case pair(code: String)
    /// Silently re-authenticate a remembered pairing (no code needed) using the
    /// session token issued at first pair. See PRD `fiple-pairing`.
    case reconnect(token: String)
    /// A short-lived side channel (the share extension) authenticating with the
    /// same token WITHOUT claiming the main peer slot — so it never evicts the
    /// app's live connection (which would immediately reconnect and kill the
    /// guest mid-transfer). Guests may only beam files and set the clipboard.
    case guestReconnect(token: String)
    /// Trigger a tile by id.
    case run(tileID: UUID)
    /// Trigger a single Fiple Bar action by id. The client sends only the id;
    /// the Mac resolves it against its own saved Fiple Bar / tiles and runs it
    /// only if it exists — so a client can never have the Mac execute an
    /// arbitrary, client-supplied action.
    case runAction(actionID: UUID)
    /// Perform a recognized multi-touch gesture on the Mac's frontmost app.
    /// A closed, named vocabulary (see ``GestureAction``) — never arbitrary input.
    case gesture(GestureAction)
    /// Ask for a Smart Trash candidate's thumbnail (fetched lazily per visible
    /// grid cell). The Mac answers with `trashThumbnail` or ignores unknown ids.
    case trashThumbnail(candidateID: UUID)
    /// Review decision for a batch of Smart Trash candidates. Ids only — the
    /// Mac resolves them against its own candidate store and acts solely on
    /// matches (server-authoritative, like `runAction`).
    case trashAction(ids: [UUID], decision: TrashDecision)
    /// Start beaming a file to the Mac's Downloads. Chunks follow; frames cap
    /// at 8 MB (and Data rides as base64), hence the chunked transfer.
    case beamBegin(transferID: UUID, name: String, totalBytes: Int64)
    /// One ~1 MB slice of the file, in order.
    case beamChunk(transferID: UUID, bytes: Data)
    /// The file is complete — the Mac finalizes it into ~/Downloads and
    /// answers with `beamResult`.
    case beamEnd(transferID: UUID)
    /// Put text on the Mac's clipboard (the QR / live-text bridge).
    case setClipboard(text: String)
    /// Ask the Mac to open the Fiple download page in its browser (the phone's
    /// terminal explainer: downloading the full Mac build is a Mac-side act).
    /// Deliberately payload-free — the Mac opens ITS OWN hardcoded URL, so the
    /// phone can never steer the Mac's browser anywhere else (ActionPolicy
    /// stance: no arbitrary content execution from the peer).
    case openDownloadPage
}

/// The phone's verdict on Smart Trash candidates.
public enum TrashDecision: String, Sendable, Equatable, Codable {
    /// Move to the system macOS Trash now.
    case trash
    /// Keep forever — excluded from all future scans.
    case keep
}

extension ClientMessage: WireTypeTagged {
    /// Message types this build understands. A peer running a newer protocol
    /// may send types outside this set; they are skipped, not treated as fatal.
    public static let knownTypes: Set<String> = Set(Tag.allCases.map(\.rawValue))
}

extension ClientMessage: Codable {
    private enum Tag: String, Codable, CaseIterable {
        case pair, reconnect, guestReconnect, run, runAction, gesture, trashThumbnail, trashAction,
             beamBegin, beamChunk, beamEnd, setClipboard, openDownloadPage
    }
    private enum CodingKeys: String, CodingKey {
        case type, code, token, tileID, actionID, version, action, candidateID, ids, decision,
             transferID, name, totalBytes, bytes, text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .pair: self = .pair(code: try c.decode(String.self, forKey: .code))
        case .reconnect: self = .reconnect(token: try c.decode(String.self, forKey: .token))
        case .guestReconnect: self = .guestReconnect(token: try c.decode(String.self, forKey: .token))
        case .run: self = .run(tileID: try c.decode(UUID.self, forKey: .tileID))
        case .runAction: self = .runAction(actionID: try c.decode(UUID.self, forKey: .actionID))
        case .gesture:
            // Tolerate an unknown gesture from a newer phone by decoding it to
            // the receive-only .unknown sentinel (a no-op on the Mac) rather than
            // throwing — a malformed known type would tear the session down.
            let raw = try c.decode(String.self, forKey: .action)
            self = .gesture(GestureAction(rawValue: raw) ?? .unknown)
        case .trashThumbnail:
            self = .trashThumbnail(candidateID: try c.decode(UUID.self, forKey: .candidateID))
        case .trashAction:
            // Tolerate an unknown decision from a newer peer by treating it as
            // the non-destructive one.
            let raw = try c.decode(String.self, forKey: .decision)
            self = .trashAction(
                ids: try c.decode([UUID].self, forKey: .ids),
                decision: TrashDecision(rawValue: raw) ?? .keep
            )
        case .beamBegin:
            self = .beamBegin(
                transferID: try c.decode(UUID.self, forKey: .transferID),
                name: try c.decode(String.self, forKey: .name),
                totalBytes: try c.decode(Int64.self, forKey: .totalBytes)
            )
        case .beamChunk:
            self = .beamChunk(
                transferID: try c.decode(UUID.self, forKey: .transferID),
                bytes: try c.decode(Data.self, forKey: .bytes)
            )
        case .beamEnd:
            self = .beamEnd(transferID: try c.decode(UUID.self, forKey: .transferID))
        case .setClipboard:
            self = .setClipboard(text: try c.decode(String.self, forKey: .text))
        case .openDownloadPage:
            self = .openDownloadPage
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pair(code):
            try c.encode(Tag.pair, forKey: .type)
            try c.encode(code, forKey: .code)
            try c.encode(FipleService.protocolVersion, forKey: .version)
        case let .reconnect(token):
            try c.encode(Tag.reconnect, forKey: .type)
            try c.encode(token, forKey: .token)
            try c.encode(FipleService.protocolVersion, forKey: .version)
        case let .guestReconnect(token):
            try c.encode(Tag.guestReconnect, forKey: .type)
            try c.encode(token, forKey: .token)
            try c.encode(FipleService.protocolVersion, forKey: .version)
        case let .run(tileID):
            try c.encode(Tag.run, forKey: .type)
            try c.encode(tileID, forKey: .tileID)
        case let .runAction(actionID):
            try c.encode(Tag.runAction, forKey: .type)
            try c.encode(actionID, forKey: .actionID)
        case let .gesture(action):
            try c.encode(Tag.gesture, forKey: .type)
            try c.encode(action.rawValue, forKey: .action)
        case let .trashThumbnail(candidateID):
            try c.encode(Tag.trashThumbnail, forKey: .type)
            try c.encode(candidateID, forKey: .candidateID)
        case let .trashAction(ids, decision):
            try c.encode(Tag.trashAction, forKey: .type)
            try c.encode(ids, forKey: .ids)
            try c.encode(decision.rawValue, forKey: .decision)
        case let .beamBegin(transferID, name, totalBytes):
            try c.encode(Tag.beamBegin, forKey: .type)
            try c.encode(transferID, forKey: .transferID)
            try c.encode(name, forKey: .name)
            try c.encode(totalBytes, forKey: .totalBytes)
        case let .beamChunk(transferID, bytes):
            try c.encode(Tag.beamChunk, forKey: .type)
            try c.encode(transferID, forKey: .transferID)
            try c.encode(bytes, forKey: .bytes)
        case let .beamEnd(transferID):
            try c.encode(Tag.beamEnd, forKey: .type)
            try c.encode(transferID, forKey: .transferID)
        case let .setClipboard(text):
            try c.encode(Tag.setClipboard, forKey: .type)
            try c.encode(text, forKey: .text)
        case .openDownloadPage:
            try c.encode(Tag.openDownloadPage, forKey: .type)
        }
    }
}

/// Why a pairing or reconnect attempt was rejected, so the remote can react
/// distinctly (e.g. surface a lockout) rather than treating every rejection as
/// a wrong code.
public enum PairRejectReason: String, Sendable, Equatable, Codable {
    /// Wrong 4-digit code.
    case incorrectCode
    /// Too many wrong codes; pairing is temporarily locked and the code rotated.
    case tooManyAttempts
    /// A remembered reconnect token no longer matches (pairing was cleared).
    case pairingExpired
}

/// Messages sent from the Mac companion to the iPhone remote.
public enum ServerMessage: Sendable, Equatable {
    /// Pairing succeeded; identifies the Mac and returns the session token the
    /// phone stores to reconnect later without re-entering the code.
    case paired(macID: String, macName: String, token: String)
    /// The Mac's hardware family, sent right after `paired` (on every connect)
    /// so the remote can show the right device icon. A separate message rather
    /// than a field on `paired` so older peers simply skip it.
    case deviceInfo(macKind: MacKind)
    /// Pairing rejected, with a typed reason.
    case pairRejected(reason: PairRejectReason)
    /// The current tile list (sent on connect and whenever tiles change).
    case tilesSnapshot(tiles: [Tile])
    /// The current Fiple Bar (curated quick actions; sent on connect and whenever
    /// the bar changes). Icons are resolved on the Mac and carried here.
    case fipleBar(actions: [Action])
    /// Per-action result of a triggered tile.
    case runResult(RunResult)
    /// Advertises the privileged terminal service on this Mac: whether it is
    /// enabled and, if so, the TCP port its TLS-PSK listener is bound to. Sent
    /// on connect and whenever the Mac toggles the feature. The phone connects
    /// to `port` on the Mac's resolved address, deriving the channel PSK from the
    /// same pairing token (ADR-0005). Older remotes skip this unknown type.
    case terminalService(enabled: Bool, port: UInt16)
    /// The current Smart Trash candidate list (metadata only — files stay on
    /// disk). Sent on connect when the feature is enabled and re-pushed after
    /// every change (new scan, review action, deadline enforcement).
    case trashCandidates(candidates: [TrashCandidate])
    /// One candidate's QuickLook thumbnail (JPEG), answering `trashThumbnail`.
    case trashThumbnail(candidateID: UUID, jpeg: Data)
    /// Typed outcome of a `trashAction`: which ids were trashed / kept, and
    /// which the Mac didn't recognize (already evicted or forged).
    case trashActionResult(trashed: [UUID], kept: [UUID], unknown: [UUID])
    /// Outcome of a beamed file: sent on `beamEnd` (landed in Downloads) or
    /// mid-transfer on a fatal error (over cap, disk, superseded).
    case beamResult(transferID: UUID, ok: Bool, message: String?)
}

extension ServerMessage: WireTypeTagged {
    /// Message types this build understands (see ``ClientMessage/knownTypes``).
    public static let knownTypes: Set<String> = Set(Tag.allCases.map(\.rawValue))
}

extension ServerMessage: Codable {
    private enum Tag: String, Codable, CaseIterable {
        case paired, deviceInfo, pairRejected, tilesSnapshot, fipleBar, runResult,
             terminalService, trashCandidates, trashThumbnail, trashActionResult, beamResult
    }
    private enum CodingKeys: String, CodingKey {
        case type, macID, macName, macKind, token, reason, tiles, actions, result, version,
             enabled, terminalPort, candidates, candidateID, jpeg, trashed, kept, unknown,
             transferID, ok, message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .paired:
            self = .paired(
                macID: try c.decode(String.self, forKey: .macID),
                macName: try c.decode(String.self, forKey: .macName),
                token: try c.decode(String.self, forKey: .token)
            )
        case .deviceInfo:
            // Tolerate an unknown family from a newer peer rather than failing
            // to decode; fall back to the app's original laptop assumption.
            let raw = try c.decode(String.self, forKey: .macKind)
            self = .deviceInfo(macKind: MacKind(rawValue: raw) ?? .laptop)
        case .pairRejected:
            // Tolerate an unknown reason from a newer peer rather than failing
            // to decode the whole message.
            let raw = try c.decode(String.self, forKey: .reason)
            self = .pairRejected(reason: PairRejectReason(rawValue: raw) ?? .incorrectCode)
        case .tilesSnapshot:
            self = .tilesSnapshot(tiles: try c.decode([Tile].self, forKey: .tiles))
        case .fipleBar:
            self = .fipleBar(actions: try c.decode([Action].self, forKey: .actions))
        case .runResult:
            self = .runResult(try c.decode(RunResult.self, forKey: .result))
        case .terminalService:
            self = .terminalService(
                enabled: try c.decode(Bool.self, forKey: .enabled),
                port: try c.decode(UInt16.self, forKey: .terminalPort)
            )
        case .trashCandidates:
            self = .trashCandidates(candidates: try c.decode([TrashCandidate].self, forKey: .candidates))
        case .trashThumbnail:
            self = .trashThumbnail(
                candidateID: try c.decode(UUID.self, forKey: .candidateID),
                jpeg: try c.decode(Data.self, forKey: .jpeg)
            )
        case .trashActionResult:
            self = .trashActionResult(
                trashed: try c.decode([UUID].self, forKey: .trashed),
                kept: try c.decode([UUID].self, forKey: .kept),
                unknown: try c.decode([UUID].self, forKey: .unknown)
            )
        case .beamResult:
            self = .beamResult(
                transferID: try c.decode(UUID.self, forKey: .transferID),
                ok: try c.decode(Bool.self, forKey: .ok),
                message: try c.decodeIfPresent(String.self, forKey: .message)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .paired(macID, macName, token):
            try c.encode(Tag.paired, forKey: .type)
            try c.encode(macID, forKey: .macID)
            try c.encode(macName, forKey: .macName)
            try c.encode(token, forKey: .token)
            try c.encode(FipleService.protocolVersion, forKey: .version)
        case let .deviceInfo(macKind):
            try c.encode(Tag.deviceInfo, forKey: .type)
            try c.encode(macKind.rawValue, forKey: .macKind)
        case let .pairRejected(reason):
            try c.encode(Tag.pairRejected, forKey: .type)
            try c.encode(reason.rawValue, forKey: .reason)
        case let .tilesSnapshot(tiles):
            try c.encode(Tag.tilesSnapshot, forKey: .type)
            try c.encode(tiles, forKey: .tiles)
        case let .fipleBar(actions):
            try c.encode(Tag.fipleBar, forKey: .type)
            try c.encode(actions, forKey: .actions)
        case let .runResult(result):
            try c.encode(Tag.runResult, forKey: .type)
            try c.encode(result, forKey: .result)
        case let .terminalService(enabled, port):
            try c.encode(Tag.terminalService, forKey: .type)
            try c.encode(enabled, forKey: .enabled)
            try c.encode(port, forKey: .terminalPort)
        case let .trashCandidates(candidates):
            try c.encode(Tag.trashCandidates, forKey: .type)
            try c.encode(candidates, forKey: .candidates)
        case let .trashThumbnail(candidateID, jpeg):
            try c.encode(Tag.trashThumbnail, forKey: .type)
            try c.encode(candidateID, forKey: .candidateID)
            try c.encode(jpeg, forKey: .jpeg)
        case let .trashActionResult(trashed, kept, unknown):
            try c.encode(Tag.trashActionResult, forKey: .type)
            try c.encode(trashed, forKey: .trashed)
            try c.encode(kept, forKey: .kept)
            try c.encode(unknown, forKey: .unknown)
        case let .beamResult(transferID, ok, message):
            try c.encode(Tag.beamResult, forKey: .type)
            try c.encode(transferID, forKey: .transferID)
            try c.encode(ok, forKey: .ok)
            try c.encodeIfPresent(message, forKey: .message)
        }
    }
}
