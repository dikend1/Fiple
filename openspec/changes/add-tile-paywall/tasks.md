## 0. Gating prerequisites (human-only, before any code)

- [ ] 0.1 New ADR `adr/0003-monetization-entitlement-dependency.md` written and
  **accepted** — ratifies adding the RevenueCat + App Store cloud dependency for
  monetization while keeping the LAN control path cloud-free (amends ADR-0001's
  no-cloud scope).
- [ ] 0.2 PRD for free tier + Pro paywall written and **accepted** (free-tile
  count, pricing intent, paywall copy, trial decision).
- [ ] 0.3 BRD updated with the revenue model.

## 1. Store + RevenueCat setup (no app code)

- [ ] 1.1 App Store Connect: create `pro_monthly` ($2.99) and `pro_yearly`
  ($14.99) auto-renewing in one subscription group, and `pro_lifetime` ($39.99)
  non-consumable; localized prices; Terms & Privacy URLs.
- [ ] 1.2 RevenueCat: project + entitlement `pro`; attach all three products;
  build the default Offering with the three packages (Yearly highlighted).

## 2. iOS implementation

> Built behind a `ProEntitlementBackend` protocol with a zero-dependency
> `LocalProBackend` stand-in, so the gate + paywall build, run, and unit-test
> today. RevenueCat becomes a one-file adapter conforming to the same protocol
> once the account/key/products exist (2.1 + §1). Logic implemented on the
> pre-acceptance go-ahead from the user (2026-06-30); docs still need formal
> accept (§0) before this is considered shippable.

- [~] 2.1 RevenueCat SDK added to `FipleiOS` via SwiftPM (`project.yml`:
  `RevenueCat` from 5.0.0) — first third-party dependency. `RevenueCatProBackend`
  adapter written (offerings → `ProProduct`, purchase/restore, `pro` entitlement,
  StoreKit 2). `EntitlementStore` auto-selects it when Info.plist
  `RevenueCatAPIKey` is set, else the local stub. **Owner action remaining:** put
  the public SDK key in `RevenueCatAPIKey`, create the 3 products in App Store
  Connect, link them under entitlement `pro` + a default Offering in RevenueCat.
- [x] 2.2 `EntitlementStore` (observable): `active | inactive | unknown`,
  cache-backed `isPro` that never downgrades a cached-Pro user offline.
  `Apps/FipleiOS/Entitlements/EntitlementStore.swift`. RevenueCat config lands in
  the adapter (2.1).
- [x] 2.3 Gating: pure `WorkspaceGate.lockedIDs` in FipleKit (free limit 8);
  `RemoteController.lockedWorkspaceIDs` + `run(_:)` refuses a locked tile and sets
  `paywallRequested`; Fiple Bar stays free; locked cards greyed + PRO badge in
  `WorkspaceCardView`.
- [x] 2.4 Paywall view (`Views/Paywall/PaywallView.swift`): three products,
  prices, Yearly "best value", Continue, Restore, Terms/Privacy, auto-renew
  disclosure. (System subscription-management deep link to add with 2.1.)
- [x] 2.5 Entry points: locked-tile tap opens the paywall (`MainTabView` sheet on
  `paywallRequested`); "Get Fiple Pro" row in Settings.
- [x] 2.6 Purchase/restore updates entitlement and unlocks live without restart
  (`onChange(of: store.isPro)` dismisses the paywall). Verified against
  `LocalProBackend`; sandbox verification belongs to §3 once 2.1 lands.

## 3. Verification Evidence

| Check | Command / Method | Result |
| --- | --- | --- |
| Gate logic: Pro/limit/overflow/edges | `swift test` (WorkspaceGateTests) | ✅ 5/5 pass |
| FipleKit suite intact after new file | `swift test` (FipleKit) | ✅ 55/55 pass |
| FipleiOS builds with gate + paywall | `xcodebuild -scheme FipleiOS` (iOS Simulator) | ✅ BUILD SUCCEEDED |
| FipleMac unaffected (shared FipleKit) | `xcodebuild -scheme FipleMac` (macOS) | ✅ BUILD SUCCEEDED |
| Free user: first 8 runnable, 9th locked → tap opens paywall | On-device / `-demo` with >8 workspaces | ⏳ Manual — logic built & unit-tested |
| Purchase → all unlock without restart | `LocalProBackend` build | ✅ Logic verified; ⏳ sandbox after 2.1 |
| Restore regains Pro | `LocalProBackend` | ✅ Logic verified; ⏳ sandbox after 2.1 |
| Pro user offline stays unlocked (cached) | cache-backed `isPro` | ✅ Logic verified; ⏳ device after 2.1 |
| Subscription lapse re-locks ≥ 8 | StoreKit config accelerated renewal | ⏳ Pending 2.1 |
| Mac authoring unaffected (no limit, unchanged wire) | `xcodebuild` + code review | ✅ Wire/Mac untouched |

> Code written on the user's go-ahead; formal accept of §0 (ADR-0003/PRD/BRD)
> and the RevenueCat adapter (2.1) remain before this ships.
