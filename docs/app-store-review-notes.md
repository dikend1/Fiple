# Fiple — App Review Notes

Paste the section below into **App Store Connect → App Review Information → Notes**.
Written for the Apple review team (English). Covers all six required
new-submission sections plus a macOS entitlement justification.

> ⚠️ Before submitting, replace `<SCREEN_RECORDING_URL>` with a link to a screen
> recording captured on physical devices (see section 1).

---

## 1. Screen recording (physical devices)

<SCREEN_RECORDING_URL>

The recording starts by launching the Fiple iPhone app and shows the full,
typical flow on real hardware:
1. The Fiple app running on a Mac (menu-bar companion) and the Fiple app on an
   iPhone, both on the same Wi-Fi network.
2. The iPhone discovering the Mac and pairing by entering the 4-digit code shown
   on the Mac.
3. Tapping a Workspace tile and a Fiple Bar app on the iPhone, and the
   corresponding apps / websites opening on the Mac.

There is no account, login, purchase, subscription, user-generated content, or
sensitive-data permission prompt in the app, so none appear in the recording.

## 2. App purpose

Fiple turns an iPhone into a remote control for your own Mac on the same Wi-Fi.

- **Problem it solves:** getting back into a working context on the Mac takes
  several manual steps — opening the right apps and websites one by one.
- **How it works:** on the Mac you define "Tiles." A **Workspace** is a preset of
  two or more actions (launch apps, open URLs); the **Fiple Bar** holds single
  apps/sites for one-tap launch. Tapping a tile on the iPhone runs those actions
  on the Mac, restoring the whole context at once.
- **Value:** one tap on the phone reopens an entire work setup on the Mac —
  useful for switching between "coding", "design", "meeting" contexts, etc.

## 3. Access instructions & test credentials

- **No credentials required** — Fiple has no accounts, login, or server sign-in.
- Fiple needs **two devices on the same Wi-Fi network**: the Fiple **Mac** app
  and the Fiple **iPhone** app. This is a local-network (LAN) app by design; it
  does not work with the iPhone alone.

Steps to review the main features:
1. Launch the Fiple app on a Mac and keep it running (it lives in the menu bar).
   Create at least one Workspace and add an app/website to the Fiple Bar.
2. Launch the Fiple app on an iPhone on the **same Wi-Fi**. Allow the Local
   Network permission prompt when asked.
3. The iPhone lists the discovered Mac. Pair by entering the 4-digit code shown
   in the Mac app.
4. On the iPhone, tap a Workspace card or a Fiple Bar icon — the actions run on
   the Mac.

> Because both platforms are part of the same app and Fiple only works over the
> LAN, please review the iOS and macOS apps **together on one Wi-Fi network**. If
> running the Mac companion during review isn't possible, the screen recording in
> section 1 demonstrates the complete pairing-and-launch flow end to end.

## 4. External services

Fiple has **no backend, no accounts, no analytics, and no third-party SDKs.**

- **Transport:** Bonjour (`_fiple._tcp`) discovery + a direct TCP connection
  between the iPhone and the Mac over the local network. Nothing is relayed
  through a server or the cloud. Tiles and pairing data stay on the two devices.
- **Only outbound internet request:** website icons are displayed using Google's
  public favicon endpoint (`https://www.google.com/s2/favicons?domain=…`). Only
  the public domain name of a site the user added is sent; no personal or usage
  data is transmitted. This is purely cosmetic (to show a site's icon).
- **Static pages:** `fiple.app` hosts the Privacy Policy, Terms, and Support
  pages linked from the app.

## 5. Regional differences

None. Fiple functions consistently across all regions. There is no
region-locked content, geo-restriction, or regional feature difference.

## 6. Regulated industry documentation

Not applicable. Fiple is a productivity utility and does not operate in any
regulated industry (no healthcare, finance, gambling, insurance, or legal
services).

---

## macOS entitlement justification (for Guideline 2.4.5(i))

The Mac app is sandboxed and declares only three entitlements, each actively
used:

- **`com.apple.security.network.server`** — the Mac runs a small local TCP server
  so the paired iPhone can send tile-launch commands over the LAN. This is the
  core mechanism of the app.
- **`com.apple.security.network.client`** — outbound local-network connection for
  the iPhone↔Mac link, plus the favicon lookup described in section 4.
- **`com.apple.security.app-sandbox`** — App Sandbox is enabled.

There are **no** Apple-events entitlements, **no** temporary exceptions, and
**no** iCloud/CloudKit entitlements. The app modifies no other app's data; it
only launches apps and opens URLs via standard macOS APIs.
