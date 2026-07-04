import FipleKit
import SwiftUI

/// The "Connected · MacBook Pro M3" hero card at the top of Home, driven by the
/// live connection. When not connected the whole card is a button that reopens
/// the pairing sheet — so a user who swiped the sheet away always has an obvious
/// way back into pairing (the sheet only auto-presents on a first run).
struct ConnectionCard: View {
    let controller: RemoteController

    private var connected: Bool { controller.phase == .connected }

    var body: some View {
        if connected {
            card
        } else {
            Button { controller.requestPairing() } label: { card }
                .buttonStyle(.plain)
                .accessibilityHint("Opens pairing to connect to your Mac.")
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connected ? Theme.Palette.connected : Theme.Palette.secondary)
                            .frame(width: 8, height: 8)
                        Text(connected ? "Connected" : "Not on this network")
                            .font(.fiple(14, .semibold))
                            .foregroundStyle(connected ? Theme.Palette.connected : Theme.Palette.secondary)
                    }
                    Text(controller.macName ?? "Your Mac")
                        .font(.fiple(22, .bold))
                        .foregroundStyle(Theme.Palette.label)
                    Text(connected
                         ? "Last active just now"
                         : "Workspaces need your Mac on the same Wi-Fi.")
                        .font(.fiple(14))
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                DeviceGlyph(kind: controller.macKind)
                    .frame(width: 116, height: 84)
            }

            // Obvious re-entry into pairing after the sheet has been dismissed.
            if !connected {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.fiple(15, .semibold))
                    Text("Tap to connect")
                        .font(.fiple(14, .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.fiple(12, .semibold))
                }
                .foregroundStyle(Theme.Palette.brand)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .frame(maxWidth: .infinity)
                .background(Theme.Palette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .fipleCard()
        // When disconnected this whole card is a "tap to pair" button; without an
        // explicit hit shape only the text/glyph registered taps, not the padding.
        .contentShape(Rectangle())
    }
}

/// The device illustration for the connection card, chosen from the Mac's
/// reported hardware family: the custom MacBook art for laptops, and a matching
/// SF Symbol for an iMac / Mac mini / Mac Studio / Mac Pro so the card is honest
/// about which kind of Mac is connected.
private struct DeviceGlyph: View {
    let kind: MacKind

    var body: some View {
        switch kind {
        case .laptop:
            MacBookGlyph()
        case .iMac, .desktop, .macMini, .macStudio, .macPro:
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Theme.Palette.label)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        switch kind {
        case .iMac, .desktop: "desktopcomputer"
        case .macMini: "macmini"
        case .macStudio: "macstudio"
        case .macPro: "macpro.gen3"
        case .laptop: "laptopcomputer"
        }
    }
}

/// A small vector stand-in for the MacBook artwork in the mockup — a tapered
/// aluminium body with a dark, softly-glowing display. Swap for a real asset
/// later without touching the card layout.
private struct MacBookGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let screenH = h * 0.82

            VStack(spacing: 0) {
                // Lid + screen
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#0E1116"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(
                        LinearGradient(
                            colors: [Theme.Palette.brand.opacity(0.55), .clear, Color(hex: "#1F8FFF").opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(3)
                    )
                    .frame(width: w * 0.86, height: screenH)

                // Base / hinge
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#C9CDD4"), Color(hex: "#E9ECEF"), Color(hex: "#B7BCC4")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: w, height: h * 0.10)
                    Capsule()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: w * 0.16, height: h * 0.045)
                }
            }
            .frame(width: w, height: h)
        }
    }
}

#Preview {
    ConnectionCard(controller: RemoteController())
        .padding()
        .background(Theme.Palette.background)
}
