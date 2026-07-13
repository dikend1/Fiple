import FipleKit
import SwiftUI

/// The in-app basket: everything swiped left this session. Files can still be
/// returned to the deck; "Empty (N)" is the single commit point that actually
/// moves files to the macOS Trash.
struct TrashBasketSheet: View {
    let staged: [TrashCandidate]
    let thumbnails: [UUID: Data]
    /// Disables the commit button while a batch decision is in flight.
    let actionInFlight: Bool
    let onReturn: (UUID) -> Void
    let onEmpty: () -> Void

    @Environment(\.dismiss) private var dismiss

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
                    List {
                        ForEach(staged) { candidate in
                            row(candidate)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Theme.Palette.background)
            .navigationTitle("Basket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !staged.isEmpty {
                    Button {
                        onEmpty()
                    } label: {
                        Text("Empty (\(staged.count)) — free up \(ByteCountFormatter.string(fromByteCount: stagedBytes, countStyle: .file))")
                            .font(.fiple(16, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(
                                actionInFlight ? Color.red.opacity(0.5) : .red,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control)
                            )
                    }
                    .disabled(actionInFlight)
                    .padding(Theme.Spacing.lg)
                    .background(.thinMaterial)
                }
            }
        }
    }

    private func row(_ candidate: TrashCandidate) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Group {
                if let data = thumbnails[candidate.id], let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.Palette.secondary.opacity(0.08)
                        Image(systemName: "doc.fill")
                            .foregroundStyle(Theme.Palette.secondary.opacity(0.4))
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.fileName)
                    .font(.fiple(15, .medium))
                    .foregroundStyle(Theme.Palette.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file))
                    .font(.fiple(12))
                    .foregroundStyle(Theme.Palette.secondary)
            }
            Spacer()
            Button("Put back") { onReturn(candidate.id) }
                .font(.fiple(13, .semibold))
                .buttonStyle(.bordered)
                .tint(Theme.Palette.brand)
        }
        .listRowBackground(Theme.Palette.background)
    }
}
