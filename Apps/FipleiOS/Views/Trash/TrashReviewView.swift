import FipleKit
import SwiftUI

/// The Smart Trash review screen. A summary header states the job ("N files,
/// X reclaimable"), a two-column grid of large thumbnails is multi-selected by
/// tap (no swipes — the design's explicit choice), and the Keep / Move-to-Trash
/// bar is **always visible** so the mechanic is discoverable before anything is
/// selected; the buttons carry the live selection count.
struct TrashReviewView: View {
    let controller: RemoteController

    @State private var selection: Set<UUID> = []

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 2
    )

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
                    Button(allSelected ? "Deselect All" : "Select All") {
                        selection = allSelected ? [] : Set(controller.trashCandidates.map(\.id))
                    }
                    .font(.fiple(14, .medium))
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

                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(controller.trashCandidates) { candidate in
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
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    /// States the job and the safety net in two lines, so the screen explains
    /// itself: what these files are, and that nothing is deleted permanently.
    private var summaryHeader: some View {
        let candidates = controller.trashCandidates
        let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let count = candidates.count == 1 ? "1 file" : "\(candidates.count) files"

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(count) · \(total)")
                .font(.fiple(22, .bold))
            Text("These haven't been opened in a while. Tap to select, then keep or trash — trashed files go to your Mac's Trash, never deleted permanently.")
                .font(.fiple(13))
                .foregroundStyle(Theme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Always on screen. With nothing selected the buttons are disabled and a
    /// hint says what to do; with a selection they show exactly what will happen
    /// ("Trash 3 · 1.2 GB").
    private var actionBar: some View {
        let count = selection.count
        let size = ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)

        return VStack(spacing: Theme.Spacing.sm) {
            if count == 0 {
                Text("Select files to review")
                    .font(.fiple(12, .medium))
                    .foregroundStyle(Theme.Palette.secondary)
            } else {
                Text("\(count) selected · \(size)")
                    .font(.fiple(12, .medium))
                    .foregroundStyle(Theme.Palette.secondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    apply(.keep)
                } label: {
                    Label("Keep", systemImage: "checkmark")
                        .font(.fiple(15, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Palette.brand)

                Button {
                    apply(.trash)
                } label: {
                    Label(count > 0 ? "Trash \(count)" : "Trash", systemImage: "trash")
                        .font(.fiple(15, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .disabled(count == 0 || controller.trashActionInFlight)
        }
        .animation(.easeOut(duration: 0.15), value: selection.isEmpty)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    private func apply(_ decision: TrashDecision) {
        let ids = Array(selection)
        Task { await controller.sendTrashAction(ids: ids, decision: decision) }
    }
}

/// One grid cell: a large QuickLook thumbnail (or a file-type placeholder while
/// it loads), selection ring + checkmark, file name, size, and a deadline chip
/// that turns red inside the 2-day window.
private struct TrashCandidateCell: View {
    let candidate: TrashCandidate
    let thumbnail: Data?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnailView
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) { selectionBadge }
                    .overlay(alignment: .bottomLeading) { deadlineChip }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.Palette.brand : Theme.Palette.hairline,
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.fileName)
                        .font(.fiple(13, .medium))
                        .foregroundStyle(Theme.Palette.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sizeText)
                        .font(.fiple(12))
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
            .opacity(isSelected ? 1 : 0.92)
            .scaleEffect(isSelected ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.fileName), \(sizeText), \(countdownText)\(isSelected ? ", selected" : "")")
    }

    @ViewBuilder private var thumbnailView: some View {
        if let thumbnail, let image = UIImage(data: thumbnail) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Palette.secondary.opacity(0.08))
                .overlay(
                    Image(systemName: "doc.fill")
                        .font(.fiple(28))
                        .foregroundStyle(Theme.Palette.secondary.opacity(0.5))
                )
        }
    }

    @ViewBuilder private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.fiple(20, .semibold))
            .foregroundStyle(isSelected ? Theme.Palette.brand : .white)
            .shadow(color: .black.opacity(isSelected ? 0 : 0.35), radius: 2)
            .padding(8)
    }

    /// Time-left chip on the thumbnail — the per-file urgency signal.
    private var deadlineChip: some View {
        Text(countdownText)
            .font(.fiple(10, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isUrgent ? Color.red : Color.black.opacity(0.55), in: Capsule())
            .padding(8)
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file)
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
