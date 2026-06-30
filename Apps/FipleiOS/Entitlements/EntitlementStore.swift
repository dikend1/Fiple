import FipleKit
import Foundation
import Observation

/// A purchasable Fiple Pro product, as shown on the paywall. `priceText` is the
/// store-localized display price (the backend supplies it), so the UI never
/// formats currency itself.
struct ProProduct: Identifiable, Hashable {
    enum Kind: Hashable { case monthly, yearly, lifetime }

    let id: String          // App Store / RevenueCat product identifier
    let kind: Kind
    let title: String       // "Monthly" / "Yearly" / "Lifetime"
    let priceText: String   // localized, e.g. "$14.99"
    let periodText: String? // e.g. "per year"; nil for the one-time Lifetime
    var isBestValue = false  // highlights Yearly as the value pick
}

/// Source of entitlement truth and purchase actions. The app talks only to this
/// protocol; `LocalProBackend` stands in until the RevenueCat adapter exists, so
/// swapping in RevenueCat is a one-file change with no callers affected.
@MainActor
protocol ProEntitlementBackend {
    /// Current Pro state, or `nil` when it cannot be resolved (offline / not yet
    /// fetched) so the store can fall back to its cache.
    func currentIsActive() async -> Bool?
    func products() async -> [ProProduct]
    /// Returns the resulting Pro state after the purchase.
    func purchase(_ product: ProProduct) async throws -> Bool
    /// Returns the resulting Pro state after restoring prior purchases.
    func restore() async throws -> Bool
}

/// Observable entitlement state for the iOS remote. Honors a cached entitlement
/// when live state is unknown, so a known-Pro user is never downgraded to locked
/// on a transient network failure (PRD: honest offline state).
@MainActor
@Observable
final class EntitlementStore {
    enum ProState: Equatable { case active, inactive, unknown }

    private(set) var state: ProState
    private(set) var products: [ProProduct] = []
    /// True while a purchase/restore is in flight, to drive button spinners.
    private(set) var isWorking = false

    /// Whether Pro should be honored for gating. `unknown` falls back to the last
    /// cached value rather than locking a user who already paid.
    var isPro: Bool {
        switch state {
        case .active: true
        case .inactive: false
        case .unknown: Self.cachedActive
        }
    }

    @ObservationIgnored private let backend: ProEntitlementBackend

    init(backend: ProEntitlementBackend? = nil) {
        self.backend = backend ?? Self.makeDefaultBackend()
        // Seed first paint from cache so a returning Pro user is unlocked instantly.
        state = Self.cachedActive ? .active : .unknown
    }

    /// The real RevenueCat backend when an Apple SDK key is configured (Info.plist
    /// `RevenueCatAPIKey`, an `appl_…` key). With no key: the local stub in DEBUG
    /// so the gate/paywall stay exercisable, but an inert backend in Release so a
    /// misconfigured production build never falsely grants Pro.
    private static func makeDefaultBackend() -> ProEntitlementBackend {
        if let key = apiKey, !key.isEmpty {
            FipleLog.execution.info("entitlements: using RevenueCat backend")
            return RevenueCatProBackend(apiKey: key)
        }
        #if DEBUG
        FipleLog.execution.info("entitlements: no RevenueCat key — using local stub (DEBUG)")
        return LocalProBackend()
        #else
        FipleLog.execution.error("entitlements: no RevenueCat key in Release — Pro disabled")
        return UnconfiguredProBackend()
        #endif
    }

    /// Public RevenueCat **Apple** SDK key (`appl_…`), shipped in the app bundle
    /// (it is a public key — never an `sk_…` secret key).
    static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
    }

    /// Loads products and resolves live entitlement. Leaves the cache-backed
    /// `unknown` state untouched when entitlement cannot be fetched (offline).
    func refresh() async {
        products = await backend.products()
        if let active = await backend.currentIsActive() {
            apply(active)
        }
    }

    @discardableResult
    func purchase(_ product: ProProduct) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let active = try await backend.purchase(product)
            apply(active)
            FipleLog.execution.info("purchase \(product.id): \(active ? "active" : "inactive")")
            return active
        } catch {
            FipleLog.execution.error("purchase failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func restore() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let active = try await backend.restore()
            apply(active)
            return active
        } catch {
            FipleLog.execution.error("restore failed: \(error.localizedDescription)")
            return false
        }
    }

    private func apply(_ active: Bool) {
        state = active ? .active : .inactive
        Self.cachedActive = active
    }

    #if DEBUG
    /// Debug-only: return the device to the free tier so the paywall can be
    /// exercised again. Clears the local-stub purchase and the cached
    /// entitlement. With a real RevenueCat backend, purchases are managed by
    /// Apple — this would only clear the local cache until the next refresh.
    func debugReset() {
        UserDefaults.standard.removeObject(forKey: LocalProBackend.purchasedKey)
        Self.cachedActive = false
        state = .inactive
    }
    #endif

    // MARK: - Cache (last known entitlement)

    private static let cacheKey = "fiple.pro.cachedActive"
    private static var cachedActive: Bool {
        get { UserDefaults.standard.bool(forKey: cacheKey) }
        set { UserDefaults.standard.set(newValue, forKey: cacheKey) }
    }
}

/// Inert backend used only for a Release build with no API key: reports no Pro
/// and no products, so a misconfigured production app fails safe (never unlocks)
/// rather than granting Pro for free.
@MainActor
struct UnconfiguredProBackend: ProEntitlementBackend {
    func currentIsActive() async -> Bool? { false }
    func products() async -> [ProProduct] { [] }
    func purchase(_ product: ProProduct) async throws -> Bool { false }
    func restore() async throws -> Bool { false }
}

/// Local stand-in for the entitlement backend until the RevenueCat adapter and an
/// App Store Connect product set exist (OpenSpec `add-tile-paywall` tasks 1.1/1.2).
/// Persists a purchased flag so the gate and paywall are fully exercisable in
/// builds and on-device testing. Replace with a `RevenueCatProBackend`
/// conforming to `ProEntitlementBackend` — no other code changes.
@MainActor
struct LocalProBackend: ProEntitlementBackend {
    static let purchasedKey = "fiple.pro.local.purchased"

    func currentIsActive() async -> Bool? {
        UserDefaults.standard.bool(forKey: Self.purchasedKey)
    }

    func products() async -> [ProProduct] {
        [
            ProProduct(id: "pro_monthly", kind: .monthly, title: "Monthly",
                       priceText: "$2.99", periodText: "per month"),
            ProProduct(id: "pro_yearly", kind: .yearly, title: "Yearly",
                       priceText: "$14.99", periodText: "per year", isBestValue: true),
            ProProduct(id: "pro_lifetime", kind: .lifetime, title: "Lifetime",
                       priceText: "$39.99", periodText: "one-time"),
        ]
    }

    func purchase(_ product: ProProduct) async throws -> Bool {
        UserDefaults.standard.set(true, forKey: Self.purchasedKey)
        return true
    }

    func restore() async throws -> Bool {
        UserDefaults.standard.bool(forKey: Self.purchasedKey)
    }
}
