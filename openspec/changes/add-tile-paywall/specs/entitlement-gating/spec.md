## ADDED Requirements

### Requirement: Free tile limit on the phone

The iOS app SHALL allow the user to run a per-surface free quota of items without
a paid entitlement, and SHALL present items beyond that quota as locked (not
runnable) while the `pro` entitlement is inactive. The gated surfaces and their
free quotas are the **Fiple Bar** (individual quick-launch actions) — first **8**
free — and the **Workspaces** list (multi-action presets) — first **2** free —
each limited independently in its own display order. The Mac SHALL NOT enforce or
be aware of these limits and SHALL continue to create, edit, reorder, and delete
tiles without any limit.

#### Scenario: Run a free item

- **WHEN** the user taps any of the first 8 items of a gated surface and `pro`
  is inactive
- **THEN** the item runs normally, exactly as it would for a Pro user

#### Scenario: Locked item is not runnable

- **WHEN** the user taps an item at position 9 or beyond on a gated surface and
  `pro` is inactive
- **THEN** the item does not run, and the paywall is presented instead

#### Scenario: Fewer than 9 items

- **WHEN** a gated surface holds 8 or fewer items and `pro` is inactive
- **THEN** no item on that surface is shown as locked and every item is runnable

#### Scenario: Mac authoring is never gated

- **WHEN** the user creates or reorders tiles on the Mac while a free phone is
  connected
- **THEN** the Mac applies the change with no limit, and the phone re-renders the
  updated snapshot with the free/locked boundary recomputed at position 8

### Requirement: Pro entitlement unlocks all tiles

The iOS app SHALL treat tiles as fully unlocked whenever the `pro` entitlement is
active, regardless of which product granted it. Entitlement state SHALL be read
from RevenueCat.

#### Scenario: Active Pro unlocks every tile

- **WHEN** the `pro` entitlement is active
- **THEN** all tiles are runnable and none are shown as locked

#### Scenario: Subscription lapse re-locks

- **WHEN** a user's only entitlement source is the Yearly subscription and it
  expires
- **THEN** on the next entitlement refresh, tiles at position 9 and beyond are
  shown as locked again

#### Scenario: Lifetime is permanent

- **WHEN** the user owns the Lifetime product
- **THEN** the `pro` entitlement stays active and tiles never re-lock

### Requirement: Purchase options

The paywall SHALL offer the products configured in the current RevenueCat
Offering, each granting the `pro` entitlement. The launch set is an auto-renewing
**Monthly** subscription and a non-consumable **Lifetime** purchase. The list is
data-driven from the Offering, so the product set can change without code
changes. Prices SHALL be presented localized from the store, and the app SHALL
NOT branch behavior on which product granted `pro`.

#### Scenario: Purchase Monthly

- **WHEN** the user buys the Monthly product and the purchase succeeds
- **THEN** the `pro` entitlement becomes active and all tiles unlock without an
  app restart

#### Scenario: Purchase Lifetime

- **WHEN** the user buys the Lifetime product and the purchase succeeds
- **THEN** the `pro` entitlement becomes active permanently and all tiles unlock

#### Scenario: Localized prices

- **WHEN** the paywall is shown
- **THEN** every product displays its store-localized price and each subscription
  shows its renewal period

### Requirement: Restore purchases

The iOS app SHALL provide an explicit Restore Purchases control that re-syncs the
entitlement from the store, so a user on a new device or reinstall regains Pro.

#### Scenario: Restore on a fresh install

- **WHEN** a user who previously bought Lifetime reinstalls the app and taps
  Restore Purchases
- **THEN** the `pro` entitlement is restored and all tiles unlock

#### Scenario: Nothing to restore

- **WHEN** a user with no prior purchase taps Restore Purchases
- **THEN** the app reports that no purchases were found and tiles stay gated

### Requirement: Honest offline entitlement state

The iOS app SHALL NOT downgrade a previously-Pro user to locked because of a
transient inability to reach the store. When current entitlement cannot be
resolved, the last known cached entitlement SHALL be used.

#### Scenario: Pro user opens the app offline

- **WHEN** a user whose last known state was Pro launches the app with no network
- **THEN** tiles remain unlocked based on the cached entitlement, and the app
  does not present the paywall

#### Scenario: Unknown state for a never-Pro user

- **WHEN** entitlement has never resolved as Pro and cannot be fetched
- **THEN** the app applies the free-tier limit (first 8 runnable) rather than
  unlocking everything
