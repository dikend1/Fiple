import FipleKit
import Foundation
import Network
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
    /// How many phones are currently connected to the terminal.
    private(set) var activeSessions = 0
    /// How long a detached shell keeps running before it's killed, in minutes.
    /// One of 15/30/60/90; applied live to the running service.
    private(set) var graceMinutes: Int

    static let graceOptions = [15, 30, 60, 90]

    /// Fires when the advertised (enabled, port) may have changed, so the server
    /// controller re-sends the terminal info to the connected phone.
    @ObservationIgnored var didChange: (@MainActor () -> Void)?

    @ObservationIgnored private var service: TerminalService?
    /// The pairing token the running service is keyed to, so we can detect a
    /// rotation and restart rather than serve a stale PSK.
    @ObservationIgnored private var serviceToken: String?
    /// The password verifier the running service was built with, so a password
    /// change restarts the service instead of validating against the old one.
    @ObservationIgnored private var serviceRecord: MasterPasswordRecord?

    private static let enabledKey = "com.fiple.terminal.enabled"
    private static let passwordKey = "com.fiple.terminal.password"
    private static let portKey = "com.fiple.terminal.lastPort"
    private static let graceKey = "com.fiple.terminal.graceMinutes"

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        hasPassword = Self.loadStoredRecordString() != nil
        let stored = UserDefaults.standard.integer(forKey: Self.graceKey)
        graceMinutes = Self.graceOptions.contains(stored) ? stored : 30
    }

    /// Changes how long detached shells survive. Applied live — running shells
    /// keep going and pick up the new grace on their next detach.
    func setGraceMinutes(_ minutes: Int) {
        guard Self.graceOptions.contains(minutes) else { return }
        graceMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.graceKey)
        service?.setGraceInterval(TimeInterval(minutes) * 60)
    }

    /// Sets or replaces the master password. Enabling is only allowed afterward.
    /// Notifies the server so a running/paired session can start the listener.
    ///
    /// `hasPassword` reflects whether the verifier was *actually* persisted — so
    /// a failed write leaves the toggle disabled instead of enabling a feature
    /// whose listener can never load its password.
    func setPassword(_ password: String) {
        let record = MasterPassword.make(password)
        guard let json = try? JSONEncoder().encode(record),
              let string = String(data: json, encoding: .utf8) else { return }
        hasPassword = Self.storeRecordString(string)
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
        // Already running with the same token AND password — nothing to do. A
        // changed password must restart the service, else it keeps validating
        // against the old verifier and rejects the new password.
        if service != nil, serviceToken == token, serviceRecord == record { return }
        stopService()

        // A detached shell (phone backgrounded, screen closed, network dropped)
        // keeps running for the chosen grace so you can leave and come back to a
        // long task without losing it.
        let service = TerminalService(
            pairingToken: token, passwordRecord: record,
            graceInterval: TimeInterval(graceMinutes) * 60
        )
        service.onActiveSessionsChanged = { [weak self] count in
            Task { @MainActor in self?.activeSessions = count }
        }
        do {
            // Reuse the last port so a phone with an open terminal reconnects to
            // the same target after a restart; fall back to any if it's taken.
            let preferred = UInt16(UserDefaults.standard.integer(forKey: Self.portKey))
            let boundPort = try await startService(service, preferredPort: preferred)
            self.service = service
            self.serviceToken = token
            self.serviceRecord = record
            self.port = boundPort
            UserDefaults.standard.set(Int(boundPort), forKey: Self.portKey)
            FipleLog.connection.info("terminal service listening on \(boundPort)")
        } catch {
            FipleLog.connection.error("terminal service failed to start: \(error.localizedDescription)")
            self.port = 0
        }
    }

    /// Starts the service on the preferred port, retrying on any free port if
    /// that one is unavailable.
    private func startService(_ service: TerminalService, preferredPort: UInt16) async throws -> UInt16 {
        if preferredPort != 0, let port = NWEndpoint.Port(rawValue: preferredPort) {
            if let bound = try? await service.start(port: port) { return bound }
        }
        return try await service.start(port: .any)
    }

    private func stopService() {
        service?.stop()
        service = nil
        serviceToken = nil
        serviceRecord = nil
        port = 0
        activeSessions = 0
    }

    private func loadRecord() -> MasterPasswordRecord? {
        guard let string = Self.loadStoredRecordString(),
              let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MasterPasswordRecord.self, from: data)
    }

    // MARK: - Verifier persistence
    //
    // The stored value is a PBKDF2 salt+hash (a verifier), never the password.
    // Prefer the Keychain, but a non-sandboxed build without a keychain-access
    // group can't write the data-protection keychain — so we verify the write
    // read-back and fall back to UserDefaults so the feature still works. The
    // sandboxed 1.0 build stays Keychain-only (the write succeeds there).

    /// Persists the verifier, returning whether it can be read back afterward.
    private static func storeRecordString(_ string: String) -> Bool {
        UserDefaults.standard.removeObject(forKey: passwordKey) // clear any stale fallback
        Keychain.set(string, for: passwordKey)
        if Keychain.get(passwordKey) == string { return true }

        // Keychain unavailable (non-sandboxed dev build) — fall back so the
        // terminal still works on the branch.
        FipleLog.connection.notice("terminal password: keychain unavailable, storing verifier in UserDefaults")
        UserDefaults.standard.set(string, forKey: passwordKey)
        return UserDefaults.standard.string(forKey: passwordKey) != nil
    }

    private static func loadStoredRecordString() -> String? {
        Keychain.get(passwordKey) ?? UserDefaults.standard.string(forKey: passwordKey)
    }
}
