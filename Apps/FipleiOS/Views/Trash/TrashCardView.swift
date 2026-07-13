import FipleKit
import SwiftUI

/// One candidate as a full-size deck card: the preview owns the card, with the
/// type chip / video glyph carried over from the old grid cells, and one quiet
/// caption line (name · size · countdown). The decision badges (red ✕ / green
/// ✓) fade in with the drag so the gesture explains itself.
struct TrashCardView: View {
    let candidate: TrashCandidate
    let thumbnail: Data?
    /// -1…0 fades in the trash badge, 0…1 the keep badge.
    var decisionProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            preview
            details
        }
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.hairline)
        )
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        .overlay(alignment: .topLeading) {
            decisionBadge(
                symbol: "checkmark", color: Theme.Palette.brand,
                opacity: max(0, decisionProgress)
            )
        }
        .overlay(alignment: .topTrailing) {
            decisionBadge(
                symbol: "xmark", color: .red,
                opacity: max(0, -decisionProgress)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.fileName), \(sizeText), \(countdownText)")
    }

    @ViewBuilder private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(Theme.Palette.secondary.opacity(0.08))
                if let thumbnail, let image = UIImage(data: thumbnail) {
                    // Fit, not fill: the point of the card is recognizing the
                    // file, and a document cropped to the card's tall aspect
                    // shows a zoomed corner instead of the page. The soft
                    // backdrop owns whatever the preview doesn't cover.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.fiple(56))
                        .foregroundStyle(Theme.Palette.secondary.opacity(0.4))
                }
                // A video's first frame is often near-black — the play glyph
                // says "this is a video" at a glance.
                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.fiple(44))
                        .foregroundStyle(.white.opacity(0.9), .black.opacity(0.35))
                }
            }
            .overlay(alignment: .bottomLeading) {
                // The extension chip carries the "what kind of file" signal
                // the thumbnails alone can't (a .db, a spreadsheet, a video).
                if let ext = fileExtension {
                    Text(ext)
                        .font(.fiple(10, .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(Theme.Spacing.md)
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((candidate.fileName as NSString).deletingPathExtension)
                .font(.fiple(17, .semibold))
                .foregroundStyle(Theme.Palette.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(sizeText) · \(countdownText)")
                .font(.fiple(13))
                .foregroundStyle(isUrgent ? .red : Theme.Palette.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
    }

    private func decisionBadge(symbol: String, color: Color, opacity: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.fiple(34, .bold))
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(color, in: Circle())
            .padding(Theme.Spacing.xl)
            .opacity(opacity)
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file)
    }

    /// Uppercased extension for the type chip; nil when the name has none.
    private var fileExtension: String? {
        let ext = (candidate.fileName as NSString).pathExtension
        return ext.isEmpty ? nil : ext.uppercased()
    }

    private var isVideo: Bool {
        ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(
            (candidate.fileName as NSString).pathExtension.lowercased()
        )
    }

    private var isUrgent: Bool {
        candidate.deadline.timeIntervalSinceNow <= 2 * 86_400
    }

    private var countdownText: String {
        let remaining = candidate.deadline.timeIntervalSinceNow
        guard remaining > 0 else { return "auto-trash any moment" }
        let days = Int(remaining / 86_400)
        if days >= 1 { return days == 1 ? "1 day left" : "\(days) days left" }
        let hours = max(1, Int(remaining / 3_600))
        return hours == 1 ? "1 hour left" : "\(hours) hours left"
    }
}
