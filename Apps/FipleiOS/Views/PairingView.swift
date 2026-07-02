import SwiftUI

/// Code-only entry. There is never a list of nearby Macs (PRD `fiple-pairing`);
/// discovery happens silently and the code authenticates the right Mac.
struct PairingView: View {
    let controller: RemoteController
    @State private var code = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#F7F9FC"), Color(hex: "#ECEFF6")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // A ScrollView (not a fixed VStack) so the Connect button and footer
            // stay reachable when the keyboard is up or Dynamic Type is large —
            // otherwise the button gets pushed under the keyboard and can't be
            // tapped. `minHeight` keeps the vertical spread on tall screens.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        header.padding(.top, 20)
                        statusCard.padding(.top, 30)
                        if controller.phase == .searching {
                            infoHint.padding(.top, 18)
                        }
                        codeSection.padding(.top, 26)
                        Spacer(minLength: 24)
                        footer.padding(.top, 24).padding(.bottom, 12)
                    }
                    .padding(.horizontal, 24)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("FipleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
            Text("Fiple")
                .font(.fiple(40, .bold))
                .foregroundStyle(Theme.Palette.label)
            Text("One tap back into your flow")
                .font(.fiple(17))
                .foregroundStyle(Theme.Palette.secondary)
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        HStack(spacing: 14) {
            MacScanIllustration(animating: controller.phase == .searching)
                .frame(width: 124, height: 108)

            VStack(alignment: .leading, spacing: 10) {
                statusIcon
                Text(statusTitle)
                    .font(.fiple(22, .bold))
                    .foregroundStyle(Theme.Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if controller.phase == .searching || controller.phase == .connecting {
                        ProgressView().controlSize(.small)
                    }
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.Palette.hairline)
        )
        .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
    }

    @ViewBuilder private var statusIcon: some View {
        let searching = controller.phase == .searching || controller.phase == .connecting
        let color = searching ? Theme.Palette.brandLink : Theme.Palette.connected
        ZStack {
            Circle().fill(color.opacity(0.14)).frame(width: 46, height: 46)
            Image(systemName: searching ? "wifi" : "checkmark")
                .font(.fiple(20, .semibold))
                .foregroundStyle(color)
        }
    }

    private var statusTitle: String {
        switch controller.phase {
        case .searching: "Looking for your Mac…"
        case .readyToPair: "Mac found"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        }
    }

    private var statusSubtitle: String {
        switch controller.phase {
        case .searching: "Scanning local network"
        case .readyToPair: "Enter the code to pair"
        case .connecting: "Pairing with your Mac"
        case .connected: ""
        }
    }

    // MARK: - Info hint

    private var infoHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondary)
            Text("Can't find your Mac? Make sure both devices are on the same Wi-Fi, the Fiple app is open on your Mac, and Local Network access is allowed.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondary)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Code + connect

    private var codeSection: some View {
        VStack(spacing: 16) {
            CodeEntryField(code: $code) {
                Task { await controller.submitCode(code) }
            }

            if let error = controller.pairError {
                Text(error).font(.footnote).foregroundStyle(.red)
            } else if controller.phase == .searching, code.count == 4 {
                Text("Code ready — pairing as soon as your Mac is found.")
                    .font(.footnote).foregroundStyle(Theme.Palette.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await controller.submitCode(code) }
            } label: {
                Text(connectLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .background(
                connectEnabled ? Theme.Palette.brandLink : Color(hex: "#E7EAF1"),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(connectEnabled ? Color.white : Theme.Palette.secondary)
            .disabled(!connectEnabled)
        }
    }

    private var connectEnabled: Bool {
        code.count == 4 && controller.phase != .connecting
    }

    private var connectLabel: String {
        switch controller.phase {
        case .connecting: return "Connecting…"
        case .searching: return code.count == 4 ? "Pair when found" : "Connect"
        default: return "Connect"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.Palette.brandLink.opacity(0.10)).frame(width: 40, height: 40)
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.brandLink)
            }
            Text("Enter the code shown in the Fiple menu-bar app on your Mac.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondary)
        }
    }
}

/// The "scanning for a Mac" illustration: a small MacBook sitting on concentric
/// pulse rings that animate while discovery is in flight.
private struct MacScanIllustration: View {
    var animating: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(Array([1.0, 0.7, 0.44].enumerated()), id: \.offset) { i, scale in
                Circle()
                    .fill(Theme.Palette.brandLink.opacity(0.05 + Double(i) * 0.035))
                    .frame(width: 116 * scale, height: 116 * scale)
                    .scaleEffect(animating && pulse ? 1.07 : 1.0)
                    .animation(
                        animating
                            ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(i) * 0.2)
                            : .default,
                        value: pulse
                    )
            }
            laptop
        }
        .onAppear { pulse = true }
    }

    private var laptop: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "#15181E"))
                    .frame(width: 72, height: 48)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#6FA0F4"), Color(hex: "#3B6FE0")],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 64, height: 40)
            }
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color(hex: "#C3CAD6"))
                .frame(width: 88, height: 6)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
    }
}
