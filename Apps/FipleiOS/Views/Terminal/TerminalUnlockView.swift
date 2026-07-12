import FipleKit
import SwiftUI

/// The dark, terminal-styled master-password screen — shown for BOTH the
/// first-time entry and the wrong-password retry, so the two never diverge
/// into a plain Form vs. this styled view. Green logo badge, a monospace field
/// with an inline reveal toggle, and a full-width brand-green Connect.
struct TerminalUnlockView: View {
    /// The line under the title — lets the caller distinguish first unlock
    /// ("Set…"/"Enter…") from a retry ("That didn't match…").
    var subtitle: String = "Enter the master password you set on your Mac."
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focused: Bool

    private var canConnect: Bool { password.count >= 4 }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 18) {
                Image("FipleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                VStack(spacing: 8) {
                    Text("Unlock terminal")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            field

            VStack(spacing: 12) {
                Button(action: submit) {
                    Text("Connect")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(canConnect ? Theme.Palette.brand : Color.white.opacity(0.12))
                        )
                        .foregroundStyle(canConnect ? .white : .white.opacity(0.4))
                }
                .disabled(!canConnect)

                Button("Cancel", action: onCancel)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.35))
            ZStack(alignment: .leading) {
                if password.isEmpty {
                    Text("Master password").foregroundStyle(.white.opacity(0.3))
                }
                Group {
                    if showPassword {
                        TextField("", text: $password)
                    } else {
                        SecureField("", text: $password)
                    }
                }
                .foregroundStyle(.white)
                .tint(Theme.Palette.brand)
                .font(.system(size: 16, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(submit)
            }
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focused ? Theme.Palette.brand : Color.white.opacity(0.12),
                                lineWidth: focused ? 1.5 : 1)
                )
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        .onAppear { focused = true }
    }

    private func submit() {
        guard canConnect else { return }
        onSubmit(password)
    }
}
