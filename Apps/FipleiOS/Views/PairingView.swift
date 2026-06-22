import SwiftUI

/// Code-only entry. There is never a list of nearby Macs (PRD `fiple-pairing`);
/// discovery happens silently and the code authenticates the right Mac.
struct PairingView: View {
    let controller: RemoteController
    @State private var code = ""
    @State private var showSearchHint = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                Image("FipleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                Text("Fiple").font(.largeTitle.bold())
                Text("One tap back into your flow")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            statusLine

            if controller.phase == .searching, showSearchHint {
                Text("Can't find your Mac. Check that both devices are on the same Wi-Fi, the Fiple app is open on your Mac, and you allowed Local Network access for Fiple.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .transition(.opacity)
            }

            // Code entry is available at all times before connecting: typed while
            // still searching, it's held and submitted the moment the Mac appears.
            VStack(spacing: 16) {
                CodeEntryField(code: $code) {
                    Task { await controller.submitCode(code) }
                }

                if let error = controller.pairError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if controller.phase == .searching, code.count == 4 {
                    Text("Code ready — pairing as soon as your Mac is found.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await controller.submitCode(code) }
                } label: {
                    Text(connectLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(code.count != 4 || controller.phase == .connecting)
            }
            .padding(.horizontal, 40)

            Spacer()
            Text("Enter the code shown in the Fiple menu-bar app on your Mac.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .task(id: controller.phase) {
            showSearchHint = false
            guard controller.phase == .searching else { return }
            try? await Task.sleep(for: .seconds(6))
            if controller.phase == .searching {
                withAnimation { showSearchHint = true }
            }
        }
    }

    private var connectLabel: String {
        switch controller.phase {
        case .connecting: return "Connecting…"
        case .searching: return code.count == 4 ? "Pair when found" : "Connect"
        default: return "Connect"
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch controller.phase {
        case .searching:
            Label("Looking for your Mac…", systemImage: "wifi")
                .foregroundStyle(.secondary)
        case .readyToPair, .connecting:
            Label("Mac found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .connected:
            EmptyView()
        }
    }
}
