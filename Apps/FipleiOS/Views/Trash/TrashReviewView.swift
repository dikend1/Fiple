import FipleKit
import SwiftUI

/// The Smart Trash review screen. One compact header line carries the shared
/// facts (count · size, the batch's nearest auto-trash date, the safety net);
/// the grid itself stays quiet — per-cell chrome appears only when it says
/// something unique (an urgent deadline, a selection). Selection follows the
/// system Photos pattern: tap to select, filled checkmark in the corner.
struct TrashReviewView: View {
    let controller: RemoteController

    @State private var selection: Set<UUID> = []
    /// Biggest first by default — the screen's promise is "free up 1,3 GB",
    /// so the files that actually deliver it lead; deadline order is one tap
    /// away for "what's about to disappear".
    @State private var sortBySize = true

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 2
    )

    private var sortedCandidates: [TrashCandidate] {
        sortBySize
            ? controller.trashCandidates.sorted { $0.sizeBytes > $1.sizeBytes }
            : controller.trashCandidates.sorted { $0.deadline < $1.deadline }
    }

    var body: some View {
        Group {
            if controller.trashCandidates.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle("Smart Trash")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.Palette.background)
        .safeAreaInset(edge: .bottom) {
            if !controller.trashCandidates.isEmpty { actionBar }
        }
        .toolbar {
            if !controller.trashCandidates.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortBySize) {
                            Label("Biggest first", systemImage: "arrow.down.circle").tag(true)
                            Label("Deadline first", systemImage: "clock").tag(false)
                        }
                        Divider()
                        Button(allSelected ? "Deselect All" : "Select All") {
                            selection = allSelected ? [] : Set(controller.trashCandidates.map(\.id))
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.fiple(16, .medium))
                    }
                }
            }
        }
        // Candidates the Mac evicted (used again / already handled) leave the
        // selection too, so the action bar never operates on ghosts.
        .onChange(of: controller.trashCandidates) { _, candidates in
            let ids = Set(candidates.map(\.id))
            selection = selection.intersection(ids)
        }
    }

    private var allSelected: Bool {
        selection.count == controller.trashCandidates.count
    }

    private var selectedBytes: Int64 {
        controller.trashCandidates
            .filter { selection.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.fiple(34))
                .foregroundStyle(Theme.Palette.secondary)
            Text("All clean")
                .font(.fiple(17, .semibold))
            Text("When files in your Mac's scanned folders go unused, they'll show up here for a quick clean-up.")
                .font(.fiple(14))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                summaryHeader

                LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                    ForEach(sortedCandidates) { candidate in
                        TrashCandidateCell(
                            candidate: candidate,
                            thumbnail: controller.trashThumbnails[candidate.id],
                            isSelected: selection.contains(candidate.id)
                        ) {
                            if selection.contains(candidate.id) {
                                selection.remove(candidate.id)
                            } else {
                                selection.insert(candidate.id)
                            }
                        }
                        .task { await controller.requestTrashThumbnail(candidate.id) }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    /// The shared facts, said once: count · size on the first line; the batch
    /// deadline and the safety net in one short secondary line.
    private var summaryHeader: some View {
        let candidates = controller.trashCandidates
        let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let count = candidates.count == 1 ? "1 file" : "\(candidates.count) files"

        return VStack(alignment: .leading, spacing: 3) {
            Text("\(count) · \(total)")
                .font(.fiple(22, .bold))
            Text("\(deadlineText(candidates)) · recoverable from the Mac's Trash")
                .font(.fiple(13))
                .foregroundStyle(Theme.Palette.secondary)
        }
    }

    private func deadlineText(_ candidates: [TrashCandidate]) -> String {
        guard let nearest = candidates.map(\.deadline).min() else { return "" }
        let days = Int(nearest.timeIntervalSinceNow / 86_400)
        if days <= 0 { return "Auto-trash starts today" }
        return days == 1 ? "Auto-trash in 1 day" : "Auto-trash in \(days) days"
    }

    /// Always visible so the mechanic needs no discovery. Keep is quiet (it's
    /// the safe no-op); Move to Trash is the one prominent action and carries
    /// the live count. Both disabled until something is selected.
    private var actionBar: some View {
        let count = selection.count
        let size = ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)

        return VStack(spacing: 6) {
            Text(count == 0 ? "Tap files to select" : "\(count) selected · \(size)")
                .font(.fiple(12))
                .foregroundStyle(Theme.Palette.secondary)
                .contentTransition(.numericText())
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    apply(.keep)
                } label: {
                    Text("Keep")
                        .font(.fiple(15, .semibold))
                        .foregroundStyle(Theme.Palette.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Palette.hairline))
                }
                .buttonStyle(.plain)

                Button {
                    apply(.trash)
                } label: {
                    Text(count > 0 ? "Move \(count) to Trash" : "Move to Trash")
                        .font(.fiple(15, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .disabled(count == 0 || controller.trashActionInFlight)
        }
        .animation(.easeOut(duration: 0.15), value: selection.isEmpty)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.bar)
    }

    private func apply(_ decision: TrashDecision) {
        let ids = Array(selection)
        Task { await controller.sendTrashAction(ids: ids, decision: decision) }
    }
}

/// One grid cell, Photos-style: the thumbnail on a soft well, a filled brand
/// checkmark in the corner only when selected, and a red "time left" chip only
/// when this file's deadline is inside the urgent 2-day window — cells whose
/// deadline matches the batch header stay chrome-free.
private struct TrashCandidateCell: View {
    let candidate: TrashCandidate
    let thumbnail: Data?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.Palette.secondary.opacity(0.08))
                    thumbnailImage
                    // A video's first frame is often near-black — the play glyph
                    // says "this is a video" at a glance.
                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.fiple(30))
                            .foregroundStyle(.white.opacity(0.9), .black.opacity(0.35))
                    }
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.fiple(22, .semibold))
                            .foregroundStyle(.white, Theme.Palette.brand)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    // The extension chip carries the "what kind of file" signal
                    // the thumbnails alone can't (a .db, a spreadsheet, a video).
                    if let ext = fileExtension {
                        Text(ext)
                            .font(.fiple(9, .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isUrgent {
                        Text(countdownText)
                            .font(.fiple(10, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.red, in: Capsule())
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? Theme.Palette.brand : Theme.Palette.hairline,
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.fileName)
                        .font(.fiple(13, .medium))
                        .foregroundStyle(Theme.Palette.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sizeText)
                        .font(.fiple(11))
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .padding(.horizontal, 2)
            }
            .animation(.easeOut(duration: 0.12), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.fileName), \(sizeText), \(countdownText) left\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var thumbnailImage: some View {
        if let thumbnail, let image = UIImage(data: thumbnail) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "doc.fill")
                .font(.fiple(28))
                .foregroundStyle(Theme.Palette.secondary.opacity(0.4))
        }
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
        guard remaining > 0 else { return "any moment" }
        let days = Int(remaining / 86_400)
        if days >= 1 { return days == 1 ? "1 day" : "\(days) days" }
        let hours = max(1, Int(remaining / 3_600))
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}
