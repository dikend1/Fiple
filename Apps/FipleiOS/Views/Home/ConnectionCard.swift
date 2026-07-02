import SwiftUI

/// The "Connected · MacBook Pro M3" hero card at the top of Home, driven by the
/// live connection.
struct ConnectionCard: View {
    let controller: RemoteController
    /// Opens the Files tab from the off-network hint.
    var onOpenFiles: () -> Void = {}

    private var connected: Bool { controller.phase == .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connected ? Theme.Palette.connected : Theme.Palette.secondary)
                            .frame(width: 8, height: 8)
                        Text(connected ? "Connected" : "Not on this network")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(connected ? Theme.Palette.connected : Theme.Palette.secondary)
                    }
                    Text(controller.macName ?? "Your Mac")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Palette.label)
                    Text(connected
                         ? "Last active just now"
                         : "Workspaces need your Mac on the same Wi-Fi.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                MacBookGlyph()
                    .frame(width: 116, height: 84)
            }

            // Reassure (and make clear to a reviewer) that files still work
            // off-network — the app isn't broken, it just has two modes.
            if !connected {
                Button(action: onOpenFiles) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Your files are available anywhere")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.brand)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm + 2)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Palette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .fipleCard()
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
