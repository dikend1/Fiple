import AppKit
import FipleKit
import SwiftUI

/// The menu-bar popover: connection status, pairing code, and quick actions.
struct MenuContentView: View {
    let server: ServerController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // The real app icon (dark squircle + white F) — always on-brand
                // and visible on the dark popover, unlike the flat logo asset.
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                Text("Fiple").font(.headline)
                Spacer()
                statusBadge
            }

            Divider()

            switch server.status {
            case .connected:
                Label("iPhone connected", systemImage: "iphone.gen3")
                    .foregroundStyle(.green)
            case .advertising, .idle:
                if let code = server.pairingCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter this code on your iPhone")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(code.value)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .tracking(8)
                            .accessibilityLabel(DevicesView.spokenPairingCode(code.value))
                    }
                } else {
                    Text("Starting…").foregroundStyle(.secondary)
                }
            }

            Divider()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Fiple…", systemImage: "macwindow")
            }
            if server.status == .connected {
                Button { Task { await server.disconnect() } } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            }
            Button { NSApplication.shared.terminate(nil) } label: {
                Label("Quit Fiple", systemImage: "power")
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 264)
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusText: String {
        switch server.status {
        case .idle: "Off"
        case .advertising: "Waiting"
        case .connected: "Connected"
        }
    }

    private var statusColor: Color {
        switch server.status {
        case .idle: .secondary
        case .advertising: .orange
        case .connected: .green
        }
    }
}
