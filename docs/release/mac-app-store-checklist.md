# Release Checklist — Fiple 1.0.0 (Mac App Store + iOS, Universal Purchase)

Distribution decision: **Mac App Store** for the Mac app, **App Store** for iOS,
shipped together as a **Universal Purchase** (shared bundle id `com.fiple.Fiple`).
Status legend: ✅ done · 🔧 actionable in-repo · 🙋 needs you (App Store Connect /
device / signing).

## 1. Build config & bundle (in-repo)

- ✅ `MARKETING_VERSION 1.0.0`, `CURRENT_PROJECT_VERSION 1` (`project.yml`).
- ✅ App icons present (Mac 16–1024, iOS 1024) in `Assets.xcassets`.
- ✅ App Sandbox ON (Mac); entitlements scoped (network client/server, Apple
  Events for Shortcuts). Hardened Runtime not required for MAS — current
  `ENABLE_HARDENED_RUNTIME=NO` is fine for this channel.
- ✅ Privacy manifests present (`CA92.1`, no tracking/collection); encryption
  declaration `ITSAppUsesNonExemptEncryption=false` on both.
- ✅ Local Network usage strings + `NSBonjourServices` on both; Mac Apple Events
  usage string present.
- 🔧 Set iOS `LSApplicationCategoryType` (Mac has `public.app-category.productivity`)
  — or set the category in App Store Connect instead.
- 🔧 Remove stray `fiple-appicon-1024.png` from the repo root (already in the asset
  catalogs).
- 🔧 (Recommended) Accessibility quick-wins before submit: real label on the
  Settings `Toggle`, `accessibilityLabel` on icon-only controls, make "View all"
  a real button. Reduces review/quality risk. (Separate task — touches code.)
- 🙋 Bump `CURRENT_PROJECT_VERSION` for every subsequent upload (build numbers
  must increase per platform).

## 2. App Store Connect setup

- 🙋 Create the app record under team `VXJ8BY6538`; configure **Universal
  Purchase** so iOS + macOS share `com.fiple.Fiple` in one record.
- 🙋 Category: Productivity (both). Age rating questionnaire (likely 4+).
- 🙋 **App Privacy → Data Not Collected** (matches the privacy manifests: no data
  collected, no tracking).
- 🙋 Screenshots per platform & required sizes (iPhone 6.7"/6.5"/6.1" as needed;
  Mac 1280×800 / 1440×900 / 2560×1600 / 2880×1800). iOS portrait only (matches
  `UISupportedInterfaceOrientations`).
- 🙋 Description, keywords, promotional text, "What's New" — *pending the
  marketing-copy step (App Store skill).*
- 🙋 App Review notes: paste from `docs/release/app-review-notes.md` (LAN test
  instructions + Shortcuts entitlement justification). No demo account needed.
- 🙋 Support URL / marketing URL / privacy policy URL (App Store requires a
  privacy policy URL even when no data is collected).

## 3. Signing & build

- 🙋 Distribution certs/profiles: "Apple Distribution" + App Store provisioning
  for both bundle targets (Automatic signing can manage these in Xcode Organizer).
- 🔧 Archive commands (run locally; upload via Xcode Organizer / Transporter):
  - `xcodegen generate`
  - iOS: `xcodebuild -project Fiple.xcodeproj -scheme FipleiOS -destination 'generic/platform=iOS' archive -archivePath build/FipleiOS.xcarchive`
  - macOS: `xcodebuild -project Fiple.xcodeproj -scheme FipleMac -destination 'generic/platform=macOS' archive -archivePath build/FipleMac.xcarchive`
  - then **Validate App** + **Distribute App → App Store Connect** for each.
- 🙋 First upload may take time to process before it appears in TestFlight/ASC.

## 4. Pre-submit verification

- ✅ `cd FipleKit && swift test` → 42/42; both schemes build.
- 🙋 **On-device pairing re-test** (pending): pair iPhone↔Mac on real hardware;
  confirm 4-digit pairing, silent reconnect, tile/Fiple-Bar launch, and the
  brute-force lockout + code rotation (5 wrong codes → 30 s lockout, new code
  shown, phone gets "Too many attempts").
- 🙋 TestFlight (iOS) smoke test before public release; Mac TestFlight optional.

## 5. Submit & monitor

- 🙋 Submit for review (both platforms together).
- 🙋 Be ready to answer review questions on the Local Network + Apple Events usage
  (see review notes).

## Known release risks

- **Shortcuts entitlement** (`temporary-exception.apple-events`) may draw review
  scrutiny — justification prepared in `app-review-notes.md`. Decision: keep for
  1.0; fallback (hide Shortcuts) only if rejected.
- **Reviewer testability** — Fiple needs a paired Mac on the same Wi-Fi; the
  review notes explain how to test and that both apps are submitted together.
- **Plaintext LAN transport** is a deliberate MVP trade-off (ADR-0002); the
  encryption declaration and privacy labels are consistent with it.
