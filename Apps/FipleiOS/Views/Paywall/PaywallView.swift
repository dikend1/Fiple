import FipleKit
import SwiftUI

/// Fiple Pro paywall: unlock unlimited workspaces on the phone. Shows the three
/// products (Yearly highlighted), a purchase button, Restore, and the legal
/// links the App Store requires for subscriptions. Presented when a locked
/// workspace is tapped or from Settings → Get Fiple Pro.
struct PaywallView: View {
    let store: EntitlementStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?

    private var selected: ProProduct? {
        store.products.first { $0.id == selectedID }
            ?? store.products.first(where: \.isBestValue)
            ?? store.products.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    hero
                    benefits
                    productList
                    purchaseButton
                    footer
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
            }
            .background(Theme.Palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            if store.products.isEmpty { await store.refresh() }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() } // unlocked — nothing left to sell
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.Palette.brand.opacity(0.16)).frame(width: 84, height: 84)
                Image(systemName: "crown.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Theme.Palette.brand)
            }
            Text("Fiple Pro")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.Palette.label)
            Text("Unlock every workspace on your phone. Keep building presets on your Mac with no limits.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            benefit("square.grid.2x2.fill", "Unlimited workspaces", "Run all your presets, not just the first 8.")
            benefit("bolt.fill", "One-tap context", "Restore any working setup on your Mac instantly.")
            benefit("lock.open.fill", "One purchase, every device", "Restore Pro on a new phone anytime.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .fipleCard()
    }

    private func benefit(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Palette.brand)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Palette.label)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.Palette.secondary)
            }
        }
    }

    // MARK: Products

    private var productList: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(store.products) { product in
                productRow(product)
            }
        }
    }

    private func productRow(_ product: ProProduct) -> some View {
        let isSelected = selected?.id == product.id
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.Palette.brand : Theme.Palette.secondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(product.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.label)
                        if product.isBestValue { bestValueChip }
                    }
                    if let period = product.periodText {
                        Text(period).font(.system(size: 13)).foregroundStyle(Theme.Palette.secondary)
                    }
                }
                Spacer()
                Text(product.priceText)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Palette.label)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(isSelected ? Theme.Palette.brand : Theme.Palette.hairline,
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var bestValueChip: some View {
        Text("BEST VALUE")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.Palette.brand, in: Capsule())
    }

    // MARK: Purchase + footer

    private var purchaseButton: some View {
        Button {
            guard let product = selected else { return }
            Task { await store.purchase(product) }
        } label: {
            Group {
                if store.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(selected.map { "Continue — \($0.priceText)" } ?? "Continue")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(Theme.Palette.brand, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(.plain)
        .disabled(store.isWorking || selected == nil)
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button {
                Task { await store.restore() }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brandLink)
            }
            .buttonStyle(.plain)
            .disabled(store.isWorking)

            HStack(spacing: Theme.Spacing.lg) {
                Button("Terms") { openURL(FipleLinks.terms) }
                Button("Privacy") { openURL(FipleLinks.privacy) }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.Palette.secondary)
            .buttonStyle(.plain)

            Text("Subscriptions renew automatically until cancelled. Manage or cancel in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    PaywallView(store: EntitlementStore())
}
