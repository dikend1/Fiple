import SwiftUI

/// A four-box pairing-code entry: the OTP-style field used on the pairing
/// screen. Renders one rounded box per digit with the active slot highlighted,
/// empty slots showing a dash, and drives input through a single hidden text
/// field so the system keyboard, SMS autofill and paste all behave normally.
struct CodeEntryField: View {
    @Binding var code: String
    /// Called when the field reaches a full four digits (e.g. to auto-submit).
    var onComplete: () -> Void = {}

    private let length = 4
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // The real input: invisible, sits on top so taps and the keyboard
            // route here. The boxes below are pure presentation.
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(length))
                    if digits != code { code = digits }
                    if digits.count == length { onComplete() }
                }
                .accessibilityLabel("Pairing code")

            HStack(spacing: 12) {
                ForEach(0..<length, id: \.self) { index in
                    box(at: index)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }

    private func box(at index: Int) -> some View {
        let digits = Array(code)
        let hasDigit = index < digits.count
        let isActive = focused
            && (index == digits.count || (index == length - 1 && digits.count == length))

        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isActive ? Theme.Palette.brandLink : Theme.Palette.hairline,
                            lineWidth: isActive ? 2 : 1.5
                        )
                }
                .shadow(color: .black.opacity(0.04), radius: 7, y: 3)

            if hasDigit {
                Text(String(digits[index]))
                    .font(.fiple(30, .semibold, design: .rounded))
                    .foregroundStyle(Theme.Palette.label)
            } else if isActive {
                Caret()
            } else {
                Text("–")
                    .font(.fiple(26, .regular))
                    .foregroundStyle(Color(hex: "#C7CDD6"))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

/// A simple blinking caret for the active code slot.
private struct Caret: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.Palette.brandLink)
            .frame(width: 2, height: 30)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}

#if DEBUG
private struct CodeEntryPreview: View {
    @State private var code = ""
    var body: some View {
        CodeEntryField(code: $code)
            .padding(40)
            .background(Theme.Palette.background)
    }
}

#Preview { CodeEntryPreview() }
#endif
