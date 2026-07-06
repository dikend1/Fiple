import SwiftUI
import FipleKit

/// Full-screen terminal on the phone. Connects the encrypted channel, runs the
/// master-password handshake, and hosts the SwiftTerm view once authenticated.
///
/// Connection parameters (host, terminal port, pairing token) are passed in by
/// the caller — the Mac advertises the terminal port over the already-paired
/// tile channel. The master password is entered here (Face ID convenience is a
/// follow-up once the Keychain store lands).
struct TerminalScreen: View {
    let host: String
    let port: UInt16
    let pairingToken: String
    let masterPassword: String

    @State private var client: TerminalClient?
    @State private var status: Status = .connecting

    enum Status: Equatable {
        case connecting
        case authenticating
        case ready
        case failed(String)
        case ended
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch status {
            case .connecting, .authenticating:
                ProgressView(status == .connecting ? "Connecting…" : "Authenticating…")
                    .tint(.white).foregroundStyle(.white)
            case .ready:
                if let client {
                    VStack(spacing: 0) {
                        SwiftTermView(client: client)
                        TerminalAccessoryBar(client: client)
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            case let .failed(message):
                statusMessage("Couldn’t open terminal", message, systemImage: "exclamationmark.triangle")
            case .ended:
                statusMessage("Session ended", "The shell on the Mac closed.", systemImage: "power")
            }
        }
        .task { await run() }
        .onDisappear { client?.close() }
    }

    private func statusMessage(_ title: String, _ detail: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        }
        .foregroundStyle(.white)
    }

    private func run() async {
        let client = TerminalClient(host: host, port: port, pairingToken: pairingToken)
        self.client = client
        do {
            try await client.connect()
        } catch {
            status = .failed("Could not reach the Mac’s terminal service.")
            return
        }
        status = .authenticating
        client.authenticate(passwordProof: masterPassword, token: pairingToken)

        for await event in client.events {
            switch event {
            case .authenticated:
                status = .ready
            case let .authFailed(reason):
                status = .failed(message(for: reason))
                return
            case .ended:
                // Only meaningful before the SwiftTerm pump takes over; once
                // ready, the terminal view shows the "session ended" note.
                if status != .ready { status = .ended }
                return
            case .output:
                break // consumed by SwiftTermView once ready
            }
            if status == .ready { break } // hand the stream to SwiftTermView
        }
    }

    private func message(for reason: TerminalAuthFailReason) -> String {
        switch reason {
        case .badToken: return "This device isn’t paired with the Mac anymore."
        case .badPassword: return "Wrong master password."
        case .lockedOut: return "Too many attempts. Try again in a moment."
        case .serviceDisabled: return "Terminal is turned off on the Mac."
        }
    }
}

/// A keyboard accessory row for keys a soft keyboard lacks — Esc, Tab, arrows,
/// and Ctrl-C, the ones you actually need in a shell.
private struct TerminalAccessoryBar: View {
    let client: TerminalClient

    var body: some View {
        HStack(spacing: 8) {
            key("esc") { client.send(Data([0x1b])) }
            key("tab") { client.send(Data([0x09])) }
            key("⌃C") { client.send(Data([0x03])) }
            key("↑") { client.send(Data([0x1b, 0x5b, 0x41])) }
            key("↓") { client.send(Data([0x1b, 0x5b, 0x42])) }
            key("←") { client.send(Data([0x1b, 0x5b, 0x44])) }
            key("→") { client.send(Data([0x1b, 0x5b, 0x43])) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 40)
                .padding(.vertical, 6)
                .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
        }
    }
}
