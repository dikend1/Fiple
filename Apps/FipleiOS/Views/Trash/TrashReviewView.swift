import FipleKit
import SwiftUI

/// The Smart Trash review screen: a full-screen swipe deck (photo-cleaner
/// style). Swipe left to stage a file in the in-app basket, right to keep it
/// forever; ✕/✓ buttons mirror the gestures and Undo steps back through the
/// session's decisions. Nothing moves on the Mac until "Empty (N)" commits the
/// basket as one batch — keeps flush when leaving the screen. The session
/// lives on the controller, so leaving and re-entering keeps the basket.
struct TrashReviewView: View {
    let controller: RemoteController

    @State private var dragOffset: CGSize = .zero
    @State private var showBasket = false
    @State private var showGestureGuide = false

    /// Swipe past this many points of horizontal travel = a decision.
    private static let decisionDistance: CGFloat = 120

    private static let gestureGuideSeenKey = "com.fiple.trash.gestureGuideSeen"

    private var session: TrashReviewSession { controller.trashSession }

    var body: some View {
        Group {
            if session.total == 0 {
                allCleanState
            } else {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    deck
                    controls
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .background(Theme.Palette.background)
        .navigationTitle("Smart Trash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.total > 0 { basketButton }
        }
        .sheet(isPresented: $showBasket) {
            TrashBasketSheet(controller: controller)
        }
        .task(id: session.current?.id) { await prefetchThumbnails() }
        .onDisappear {
            let controller = controller
            Task { await controller.trashFlushKeeps() }
        }
        .onAppear {
            // Strictly once: the very first time this screen opens — marked
            // seen immediately, so leaving mid-guide (or an empty deck) never
            // re-triggers it. The DEBUG Settings row re-arms it on demand.
            if !UserDefaults.standard.bool(forKey: Self.gestureGuideSeenKey) {
                UserDefaults.standard.set(true, forKey: Self.gestureGuideSeenKey)
                showGestureGuide = true
            }
        }
        .overlay {
            if showGestureGuide { gestureGuide }
        }
    }

    // MARK: Gesture guide

    /// One-time overlay: hands + directions. Tap anywhere to start reviewing.
    private var gestureGuide: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xxl) {
                Text("Review by swiping")
                    .font(.fiple(22, .bold))
                    .foregroundStyle(.white)

                HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                    guideColumn(
                        hand: "hand.point.left.fill", badge: "xmark", color: .red,
                        title: "Swipe left",
                        caption: "into the basket —\nnothing moves until\nyou empty it"
                    )
                    guideColumn(
                        hand: "hand.point.right.fill", badge: "checkmark", color: Theme.Palette.brand,
                        title: "Swipe right",
                        caption: "keep the file —\nnever suggested\nagain"
                    )
                }

                Label("Undo takes back your last swipe", systemImage: "arrow.uturn.backward")
                    .font(.fiple(13))
                    .foregroundStyle(.white.opacity(0.75))

                Text("Tap to start")
                    .font(.fiple(15, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .padding(Theme.Spacing.xxl)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissGestureGuide() }
        .transition(.opacity)
    }

    private func guideColumn(
        hand: String, badge: String, color: Color, title: String, caption: String
    ) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 64, height: 64)
                Image(systemName: badge)
                    .font(.fiple(26, .bold))
                    .foregroundStyle(.white)
            }
            Image(systemName: hand)
                .font(.fiple(34))
                .foregroundStyle(.white)
            Text(title)
                .font(.fiple(16, .semibold))
                .foregroundStyle(.white)
            Text(caption)
                .font(.fiple(13))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func dismissGestureGuide() {
        withAnimation(.easeOut(duration: 0.2)) { showGestureGuide = false }
    }

    // MARK: Header

    /// Progress plus the shared safety-net fact, said once.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(session.reviewed) of \(session.total) reviewed")
                .font(.fiple(22, .bold))
                .contentTransition(.numericText())
            Text("Trashed files are recoverable from the Mac's Trash")
                .font(.fiple(13))
                .foregroundStyle(Theme.Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var basketButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showBasket = true
            } label: {
                Image(systemName: "trash")
                    .overlay(alignment: .topTrailing) {
                        if !session.staged.isEmpty {
                            Text("\(session.staged.count)")
                                .font(.fiple(11, .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                // The overlay is only as wide as the trash
                                // glyph, so a two-digit count would wrap into
                                // a digit stack without this.
                                .fixedSize()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.red, in: Capsule())
                                .offset(x: 12, y: -10)
                        }
                    }
            }
            .disabled(session.staged.isEmpty)
            .accessibilityLabel("Basket, \(session.staged.count) files")
        }
    }

    // MARK: Deck

    @ViewBuilder private var deck: some View {
        if let current = session.current {
            ZStack {
                if let next = session.upcoming.first {
                    TrashCardView(candidate: next, thumbnail: controller.trashThumbnails[next.id])
                        .scaleEffect(0.94)
                        .offset(y: 10)
                }
                TrashCardView(
                    candidate: current,
                    thumbnail: controller.trashThumbnails[current.id],
                    decisionProgress: decisionProgress
                )
                .offset(dragOffset)
                .rotationEffect(.degrees(dragOffset.width / 18))
                .gesture(dragGesture)
            }
            .frame(maxHeight: .infinity)
        } else {
            deckDoneState
        }
    }

    /// The ✕/✓ badge fades in with the horizontal drag, so release is never
    /// a surprise. Horizontal only — vertical swipes stay free for scrolling
    /// muscle memory and never decide anything.
    private var decisionProgress: CGFloat {
        dragOffset.width / Self.decisionDistance
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                if value.translation.width <= -Self.decisionDistance {
                    decide(.trash)
                } else if value.translation.width >= Self.decisionDistance {
                    decide(.keep)
                } else {
                    withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                }
            }
    }

    /// No candidates at all — the Mac has nothing for us.
    private var allCleanState: some View {
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

    /// Every card swiped; the basket may still hold uncommitted files.
    private var deckDoneState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: session.staged.isEmpty ? "checkmark.circle" : "trash")
                .font(.fiple(44))
                .foregroundStyle(Theme.Palette.brand)
            Text(session.staged.isEmpty
                 ? "All caught up — nothing left to review."
                 : "Deck done. Empty the basket to move \(session.staged.count) file\(session.staged.count == 1 ? "" : "s") to the Mac's Trash.")
                .font(.fiple(15))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
            if !session.staged.isEmpty {
                Button("Open Basket") { showBasket = true }
                    .font(.fiple(15, .semibold))
                    .tint(Theme.Palette.brand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: Theme.Spacing.xxl) {
            controlButton(symbol: "xmark", tint: .red, label: "Move to basket") {
                animateOff(.trash)
            }
            controlButton(
                symbol: "arrow.uturn.backward", tint: Theme.Palette.secondary,
                label: "Undo", small: true
            ) {
                withAnimation(.spring(duration: 0.3)) { controller.trashUndo() }
            }
            .disabled(!session.canUndo)
            .opacity(session.canUndo ? 1 : 0.35)
            controlButton(symbol: "checkmark", tint: Theme.Palette.brand, label: "Keep") {
                animateOff(.keep)
            }
        }
        .disabled(session.current == nil)
        .opacity(session.current == nil ? 0.35 : 1)
    }

    private func controlButton(
        symbol: String, tint: Color, label: String, small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.fiple(small ? 17 : 22, .bold))
                .foregroundStyle(tint)
                .frame(width: small ? 48 : 64, height: small ? 48 : 64)
                .background(Theme.Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline))
        }
        .accessibilityLabel(label)
    }

    // MARK: Actions

    /// Button path: fling the card off in the decision's direction, then decide.
    private func animateOff(_ decision: TrashDecision) {
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = CGSize(width: decision == .trash ? -500 : 500, height: 0)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            decide(decision)
        }
    }

    private func decide(_ decision: TrashDecision) {
        controller.trashSwipe(decision)
        dragOffset = .zero
    }

    /// Fetch the visible card and the next two so the deck never shows a blank.
    private func prefetchThumbnails() async {
        let wanted = [session.current].compactMap { $0 } + session.upcoming.prefix(2)
        for candidate in wanted {
            await controller.requestTrashThumbnail(candidate.id)
        }
    }
}
