import SwiftUI

/// Code-only entry. There is never a list of nearby Macs (PRD `fiple-pairing`);
/// discovery happens silently and the code authenticates the right Mac.
struct PairingView: View {
    let controller: RemoteController
    @State private var code = ""
    @State private var showSearchHint = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
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

            if controller.phase != .searching {
                VStack(spacing: 14) {
                    TextField("0000", text: $code)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .focused($codeFocused)
                        .onChange(of: code) { _, new in
                            code = String(new.filter(\.isNumber).prefix(4))
                        }

                    if let error = controller.pairError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    Button {
                        Task { await controller.submitCode(code) }
                    } label: {
                        Text(controller.phase == .connecting ? "Connecting…" : "Connect")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(code.count != 4 || controller.phase == .connecting)
                }
                .padding(.horizontal, 40)
            }

            Spacer()
            Text("Enter the code shown in the Fiple menu-bar app on your Mac.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .onChange(of: controller.phase) { _, phase in
            codeFocused = (phase == .readyToPair)
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
