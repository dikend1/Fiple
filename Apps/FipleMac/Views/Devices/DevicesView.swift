import SwiftUI

/// Pairing & connection page — the home for the pairing code on the Mac.
struct DevicesView: View {
    let server: ServerController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(title: "Devices", subtitle: "Pair and manage your iPhone remote.")

                card
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    @ViewBuilder private var card: some View {
        switch server.status {
        case .connected:
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.md) {
                    IconTile(iconImageData: nil, systemName: "iphone.gen3", colorHex: "#2DA44E", size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iPhone connected").font(.system(size: 16, weight: .semibold))
                        Text("Changes sync live to your remote.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect", role: .destructive) { Task { await server.disconnect() } }
                }
            }
            .padding(Theme.Spacing.xl)
            .fipleCard()

        case .advertising, .idle:
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Label("Waiting for your iPhone", systemImage: "wifi")
                    .font(.system(size: 15, weight: .semibold))
                Text("Open Fiple on your iPhone — on the same Wi-Fi — and enter this code:")
                    .font(.callout).foregroundStyle(.secondary)
                Text(server.pairingCode?.value ?? "----")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(12)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.lg)
                    .background(Accent(hex: "#3B82F6").iconBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                    .accessibilityLabel(Self.spokenPairingCode(server.pairingCode?.value))
            }
            .padding(Theme.Spacing.xl)
            .fipleCard()
        }
    }

    /// VoiceOver reads the code digit by digit ("Pairing code: 8, 4, 1, 2")
    /// instead of as one number.
    static func spokenPairingCode(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return "Pairing code not available yet" }
        return "Pairing code: " + code.map(String.init).joined(separator: ", ")
    }
}
