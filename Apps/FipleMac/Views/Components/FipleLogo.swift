import SwiftUI

/// The Fiple "F" letter-mark: a geometric F built from rounded strokes with a
/// single blue gradient washed across the whole glyph (not per-stroke), so it
/// reads as one continuous shape. Mirrors the iOS remote's mark so the two apps
/// share one identity.
struct FipleMark: View {
    var size: CGFloat = 56

    private var thickness: CGFloat { size * 0.2 }
    private var glyphWidth: CGFloat { size * 0.74 }

    var body: some View {
        LinearGradient(
            colors: [Color(hex: "#5C9DFF"), Color(hex: "#2F6BFF")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: glyphWidth, height: size)
        .mask { strokes }
    }

    private var strokes: some View {
        ZStack(alignment: .topLeading) {
            Capsule().frame(width: thickness, height: size)            // stem
            Capsule().frame(width: glyphWidth, height: thickness)      // top bar
            Capsule()
                .frame(width: glyphWidth * 0.64, height: thickness)    // middle bar
                .offset(y: size * 0.40)
        }
        .frame(width: glyphWidth, height: size, alignment: .topLeading)
    }
}

/// The Fiple app-icon tile: the mark centred on a soft white squircle with a
/// gentle blue-tinted shadow — the same treatment as the iOS Home-screen icon.
struct FipleAppIcon: View {
    var size: CGFloat = 92

    private var corner: CGFloat { size * 0.235 }

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.white)
            .frame(width: size, height: size)
            .overlay { FipleMark(size: size * 0.5) }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05))
            }
            .shadow(color: Color(hex: "#2F6BFF").opacity(0.16), radius: size * 0.13, y: size * 0.07)
            .shadow(color: .black.opacity(0.05), radius: size * 0.04, y: size * 0.02)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 40) {
        FipleMark(size: 80)
        FipleAppIcon(size: 100)
    }
    .padding(60)
}
#endif
