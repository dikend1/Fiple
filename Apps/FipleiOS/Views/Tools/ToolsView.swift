import FipleKit
import SwiftUI

/// The Tools tab: the phone→Mac utilities that don't need to crowd Home —
/// Send to Mac and Smart Trash — as a two-up grid of feature cards. Each card
/// carries a live fact (candidate count, reclaimable size), so the page reads
/// as a small dashboard rather than two thin rows adrift on an empty screen.
struct ToolsView: View {
    let controller: RemoteController

    @State private var showSendSheet = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 2
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    PageTitle("Tools")

                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        Button {
                            showSendSheet = true
                        } label: {
                            ToolCard(
                                icon: "square.and.arrow.up",
                                tint: Theme.Palette.brand,
                                title: "Send to Mac",
                                detail: "Photos & files",
                                caption: "Land in Downloads"
                            )
                        }
                        .buttonStyle(ToolCardPressStyle())
                        .disabled(!controller.isConnected)
                        .opacity(controller.isConnected ? 1 : 0.45)

                        NavigationLink {
                            TrashReviewView(controller: controller)
                        } label: {
                            ToolCard(
                                icon: "trash",
                                tint: .orange,
                                title: "Smart Trash",
                                detail: trashDetail,
                                caption: trashCaption,
                                badge: controller.trashCandidates.isEmpty
                                    ? nil : "\(controller.trashCandidates.count)"
                            )
                        }
                        .buttonStyle(ToolCardPressStyle())
                        .disabled(controller.trashCandidates.isEmpty)
                        .opacity(controller.trashCandidates.isEmpty ? 0.45 : 1)
                    }

                    if !controller.isConnected {
                        Text("Connect to your Mac on the same Wi-Fi to use tools.")
                            .font(.fiple(13))
                            .foregroundStyle(Theme.Palette.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.tabBarClearance)
            }
            .background(Theme.Palette.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showSendSheet) {
            SendToMacView(controller: controller)
                // Two picker rows don't need a full screen — a compact card
                // keeps the context (and the app) visible behind.
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
    }

    /// The live fact each card leads with.
    private var trashDetail: String {
        let candidates = controller.trashCandidates
        guard !candidates.isEmpty else { return "All clean" }
        let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return "Free up \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }

    private var trashCaption: String {
        let count = controller.trashCandidates.count
        guard count > 0 else { return "No stale files found" }
        return count == 1 ? "1 file to review" : "\(count) files to review"
    }
}

/// One square-ish feature card: tinted icon up top, the tool's name, then the
/// live fact it currently offers — with an optional count badge.
private struct ToolCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let caption: String
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.fiple(19, .semibold))
                            .foregroundStyle(tint)
                    )
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.fiple(13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint, in: Capsule())
                }
            }

            Spacer(minLength: Theme.Spacing.lg)

            Text(title)
                .font(.fiple(16, .semibold))
                .foregroundStyle(Theme.Palette.label)
            Text(detail)
                .font(.fiple(14, .medium))
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(caption)
                .font(.fiple(12))
                .foregroundStyle(Theme.Palette.secondary)
                .padding(.top, 1)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 168)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.Palette.hairline)
        )
    }
}

/// A gentle press-down so the cards feel tappable.
private struct ToolCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The screen's large title, matching Home's custom header style.
private struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.fiple(34, .bold))
            .foregroundStyle(Theme.Palette.label)
    }
}
