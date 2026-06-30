import FipleKit
import Foundation
import RevenueCat

/// Real entitlement backend backed by RevenueCat (over StoreKit 2). Resolves the
/// `pro` entitlement, lists the current Offering's packages as `ProProduct`s
/// (with store-localized prices), and runs purchase/restore. Selected
/// automatically by `EntitlementStore` when an API key is configured
/// (Info.plist `RevenueCatAPIKey`); otherwise the local stub is used.
@MainActor
final class RevenueCatProBackend: ProEntitlementBackend {
    /// The entitlement identifier configured in the RevenueCat dashboard.
    static let entitlementID = "pro"

    /// Packages from the current Offering, keyed by store product id, so a
    /// `ProProduct` chosen on the paywall can be resolved back to its package.
    private var packagesByProductID: [String: Package] = [:]

    init(apiKey: String) {
        if !Purchases.isConfigured {
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: apiKey)
                    .with(storeKitVersion: .storeKit2)
                    .build()
            )
        }
    }

    func currentIsActive() async -> Bool? {
        do {
            let info = try await Purchases.shared.customerInfo()
            return info.entitlements[Self.entitlementID]?.isActive ?? false
        } catch {
            FipleLog.execution.error("RevenueCat customerInfo failed: \(error.localizedDescription)")
            return nil // unknown — let the store fall back to cache
        }
    }

    func products() async -> [ProProduct] {
        do {
            let offerings = try await Purchases.shared.offerings()
            let packages = offerings.current?.availablePackages ?? []
            packagesByProductID = Dictionary(
                packages.map { ($0.storeProduct.productIdentifier, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return packages.map(Self.proProduct(from:))
        } catch {
            FipleLog.execution.error("RevenueCat offerings failed: \(error.localizedDescription)")
            return []
        }
    }

    func purchase(_ product: ProProduct) async throws -> Bool {
        guard let package = packagesByProductID[product.id] else {
            // Offerings not loaded yet — fetch, then retry the lookup once.
            _ = await products()
            guard let package = packagesByProductID[product.id] else { return false }
            return try await purchase(package)
        }
        return try await purchase(package)
    }

    private func purchase(_ package: Package) async throws -> Bool {
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return false }
        return result.customerInfo.entitlements[Self.entitlementID]?.isActive ?? false
    }

    func restore() async throws -> Bool {
        let info = try await Purchases.shared.restorePurchases()
        return info.entitlements[Self.entitlementID]?.isActive ?? false
    }

    // MARK: - Mapping

    private static func proProduct(from package: Package) -> ProProduct {
        let kind: ProProduct.Kind
        let period: String?
        switch package.packageType {
        case .annual:
            kind = .yearly; period = "per year"
        case .monthly:
            kind = .monthly; period = "per month"
        case .lifetime:
            kind = .lifetime; period = "one-time"
        default:
            // Custom/other: infer from the product id so non-standard package
            // configs still render sensibly.
            let id = package.storeProduct.productIdentifier.lowercased()
            if id.contains("life") { kind = .lifetime; period = "one-time" }
            else if id.contains("year") || id.contains("annual") { kind = .yearly; period = "per year" }
            else { kind = .monthly; period = "per month" }
        }
        return ProProduct(
            id: package.storeProduct.productIdentifier,
            kind: kind,
            title: kind.displayTitle,
            priceText: package.storeProduct.localizedPriceString,
            periodText: period,
            isBestValue: kind == .yearly
        )
    }
}

private extension ProProduct.Kind {
    var displayTitle: String {
        switch self {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .lifetime: "Lifetime"
        }
    }
}
