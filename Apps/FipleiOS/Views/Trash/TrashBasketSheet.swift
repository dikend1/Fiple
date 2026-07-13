import FipleKit
import SwiftUI

/// The in-app basket: everything swiped left, shown as a thumbnail grid so
/// the files are recognizable at a glance (photo-cleaner style). Any file can
/// still be put back on the deck; the red "Empty" in the toolbar is the single
/// commit point that actually moves files to the macOS Trash.
struct TrashBasketSheet: View {
    let controller: RemoteController

    @Environment(\.dismiss) private var dismiss

    private var staged: [TrashCandidate] { controller.trashSession.staged }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 3
    )

    private var stagedBytes: Int64 {
        staged.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        NavigationStack {
            Group {
                if staged.isEmpty {
                    EmptyHint(icon: "trash", text: "Nothing staged. Swipe cards left to collect files here.")
                        .padding(Theme.Spacing.lg)
                } else {
                    grid
                }
            }
            .background(Theme.Palette.background)
            .navigationTitle("Basket (\(staged.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !staged.isEmpty {
                        Button {
                            let controller = controller
                            dismiss()
                            Task { await controller.trashCommitBasket() }
                        } label: {
                            Label("Empty", systemImage: "trash")
                                .labelStyle(.titleAndIcon)
                                .font(.fiple(16, .semibold))
                        }
                        .tint(.red)
                        .disabled(controller.trashActionInFlight || controller.phase != .connected)
                    }
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("\(ByteCountFormatter.string(fromByteCount: stagedBytes, countStyle: .file)) to free up · recoverable from the Mac's Trash")
                    .font(.fiple(13))
                    .foregroundStyle(Theme.Palette.secondary)

                LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                    ForEach(staged) { candidate in
                        cell(candidate)
                            .task { await controller.requestTrashThumbnail(candidate.id) }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    /// One staged file: a big square thumbnail with a "put back" button in the
    /// corner (the reference cleaner's ↺), name + size underneath.
    private func cell(_ candidate: TrashCandidate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        Rectangle().fill(Theme.Palette.secondary.opacity(0.08))
                        if let data = controller.trashThumbnails[candidate.id],
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "doc.fill")
                                .font(.fiple(26))
                                .foregroundStyle(Theme.Palette.secondary.opacity(0.4))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline)
                )
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            controller.trashReturnToDeck(id: candidate.id)
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.fiple(13, .bold))
                            .foregroundStyle(Theme.Palette.label)
                            .frame(width: 30, height: 30)
                            .background(.white, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.Palette.hairline))
                    }
                    .padding(5)
                    .accessibilityLabel("Put \(candidate.fileName) back")
                }

            VStack(alignment: .leading, spacing: 1) {
                Text((candidate.fileName as NSString).deletingPathExtension)
                    .font(.fiple(12, .medium))
                    .foregroundStyle(Theme.Palette.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file))
                    .font(.fiple(11))
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .padding(.horizontal, 2)
        }
    }
}
