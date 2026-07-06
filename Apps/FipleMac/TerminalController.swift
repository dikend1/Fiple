import FipleKit
import Foundation
import Observation

/// Owns the Mac's privileged terminal feature: the on/off preference, the master
/// password verifier, and the `TerminalService` lifecycle. Kept separate from
/// `ServerController` so the plaintext tile channel and the encrypted terminal
/// channel stay cleanly divided (ADR-0005).
///
/// Off by default and inert until the user both enables it and sets a master
/// password. The service binds a fresh TLS-PSK listener keyed to the current
/// pairing token; when a new phone pairs (token rotates) the service restarts.
@MainActor
@Observable
final class TerminalController {
    /// Whether the user has turned the feature on. Persisted; defaults to off.
    private(set) var enabled: Bool
    /// Whether a master password has been set (its verifier is in the Keychain).
    private(set) var hasPassword: Bool
    /// The bound port of the running listener, or 0 when not running.
    private(set) var port: UInt16 = 0

    /// Fires when the advertised (enabled, port) may have changed, so the server
    /// controller re-sends the terminal info to the connected phone.
    @ObservationIgnored var didChange: (@MainActor () -> Void)?

    @ObservationIgnored private var service: TerminalService?
    /// The pairing token the running service is keyed to, so we can detect a
    /// rotation and restart rather than serve a stale PSK.
    @ObservationIgnored private var serviceToken: String?

    private static let enabledKey = "com.fiple.terminal.enabled"
    private static let passwordKey = "com.fiple.terminal.password"

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        hasPassword = Keychain.get(Self.passwordKey) != nil
    }

    /// Sets or replaces the master password. Enabling is only allowed afterward.
    /// Notifies the server so a running/paired session can start the listener.
    func setPassword(_ password: String) {
        let record = MasterPassword.make(password)
        guard let json = try? JSONEncoder().encode(record),
              let string = String(data: json, encoding: .utf8) else { return }
        Keychain.set(string, for: Self.passwordKey)
        hasPassword = true
        didChange?()
    }

    /// Turns the feature on or off. Turning on requires a password. The server
    /// controller owns the pairing token, so it does the actual listener sync
    /// (and re-advertises) in response to `didChange`.
    func setEnabled(_ on: Bool) {
        guard !on || hasPassword else { return } // can't enable without a password
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        didChange?()
    }

    /// Brings the listener in line with the current state: running (and keyed to
    /// `pairingToken`) when enabled + password set + a phone is paired; stopped
    /// otherwise. Called on pairing and whenever the toggle changes.
    func syncService(pairingToken: String?) async {
        let shouldRun = enabled && hasPassword && pairingToken != nil
        guard shouldRun, let token = pairingToken, let record = loadRecord() else {
            stopService()
            return
        }
        // Already running on the same token — nothing to do.
        if service != nil, serviceToken == token { return }
        stopService()

        let service = TerminalService(pairingToken: token, passwordRecord: record)
        do {
            let boundPort = try await service.start()
            self.service = service
            self.serviceToken = token
            self.port = boundPort
            FipleLog.connection.info("terminal service listening on \(boundPort)")
        } catch {
            FipleLog.connection.error("terminal service failed to start: \(error.localizedDescription)")
            self.port = 0
        }
    }

    private func stopService() {
        service?.stop()
        service = nil
        serviceToken = nil
        port = 0
    }

    private func loadRecord() -> MasterPasswordRecord? {
        guard let string = Keychain.get(Self.passwordKey),
              let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MasterPasswordRecord.self, from: data)
    }
}
