# App Review Notes — Fiple 1.0.0

> Paste the relevant parts into **App Store Connect → App Review Information →
> Notes**. Fiple ships as a Universal Purchase: iOS remote + macOS companion
> share bundle id `com.fiple.Fiple`. Submit both together so the reviewer can
> test end-to-end.

## What Fiple is

Fiple turns an iPhone into a remote control for a Mac on the **same Wi-Fi**. The
Mac companion app defines "tiles" (each launches apps / websites / Shortcuts) and
a "Fiple Bar" of quick actions; tapping a tile on the iPhone restores that
working context on the Mac. Tiles/remote control use the **local network only**
(no servers, no account).

Fiple also has **Remote File Access** (the **Files** tab): the Mac mirrors a
small, bounded set of recent files from Desktop/Documents/Downloads into the
user's **own private iCloud** (CloudKit private database), so the user can
browse and download them from the iPhone **from anywhere** — even when the Mac
is asleep. There is still **no Fiple server and no Fiple account**: data lives
only in the user's private iCloud, which the developer cannot access. This
feature is read-only (originals on the Mac are never modified) and free.

## How to test (important — requires two devices on one Wi-Fi)

Because Fiple is a LAN remote, the iOS app is only useful paired with the macOS
companion:

1. Install and open **Fiple for Mac** (same submission). It shows a **4-digit
   pairing code** in its menu-bar item.
2. Put the iPhone on the **same Wi-Fi** and open **Fiple**. It silently finds the
   Mac (no device list) — enter the 4-digit code.
3. Once paired, the iPhone shows the Mac's tiles and Fiple Bar. Tap any tile to
   launch its apps/URLs/Shortcuts on the Mac.

Notes for review:
- On first launch the iOS app requests **Local Network** access (to discover the
  Mac via Bonjour `_fiple._tcp`). Please allow it.
- On the Mac, the first time you add a Shortcut to a tile, macOS prompts to allow
  controlling **Shortcuts Events** (Apple Events) — please allow it.
- If a Mac for testing is unavailable, the app is **still fully navigable** — the
  tabbed UI (Home / Files / Recent / Settings) is always shown. Home clearly
  states "Not on this network" and explains that Workspaces need the Mac on the
  same Wi-Fi. Full tile functionality requires the paired Mac.

## How to test Remote File Access (Files tab — works without the same Wi-Fi)

This feature is independent of pairing and works over the internet via iCloud:

1. Sign the **Mac** and the **iPhone** into the **same Apple ID** with iCloud
   enabled.
2. On the Mac companion, open **Settings → Remote File Access** and turn it on.
   Recent files from Desktop/Documents/Downloads sync to the user's private
   iCloud.
3. On the iPhone, open the **Files** tab and pull to refresh — the recent files
   appear and can be downloaded / opened, even on a different network or with the
   Mac asleep.
4. Without iCloud signed in, the Files tab shows a clear "sign in to the same
   Apple ID" state (not an error).

## Entitlement justification (macOS)

The Mac app is sandboxed. It declares
`com.apple.security.temporary-exception.apple-events` scoped to exactly one bundle
id, `com.apple.shortcuts.events`.

- **Why:** to let the user add one of *their own* Apple Shortcuts to a tile, the
  app lists the names of installed Shortcuts via the scriptable "Shortcuts
  Events" target. The plain `com.apple.security.automation.apple-events`
  entitlement alone fails for this target with error `-600`; scoping a temporary
  exception to `com.apple.shortcuts.events` is what allows
  `get name of every shortcut` to work from inside the sandbox.
- **Scope:** read-only — it reads Shortcut **names** only, to populate a picker.
  It does not run, create, or modify Shortcuts via Apple Events (a Shortcut is
  later triggered by the user via the `shortcuts://` URL scheme).
- **Consent:** the user is prompted on first use (`NSAppleEventsUsageDescription`:
  "Fiple lists your Apple Shortcuts so you can add them to a tile.").
- **Privacy:** nothing leaves the device; no data is collected or transmitted off
  the LAN.

## Privacy & encryption

- **Data collection:** none by the developer. No tracking, no analytics, no
  accounts. Remote File Access stores the user's files in **their own private
  iCloud** (CloudKit private database) — this is the user's data, not accessible
  to the developer, so it is **not** "data collected" for App Privacy purposes.
  Privacy manifests declare local `UserDefaults` (`CA92.1`) and file-timestamp
  access to display file dates to the user (`C617.1`).
- **Network:** local network (Bonjour + TCP on the LAN) for tiles/remote control;
  Apple's iCloud/CloudKit for Remote File Access. No Fiple-operated servers.
- **iCloud:** the app uses the user's private CloudKit database (iCloud
  entitlement, container `iCloud.com.maksatov.fipleapp`). Requires the same Apple
  ID on both devices; consumes the user's iCloud storage.
- **Encryption:** `ITSAppUsesNonExemptEncryption = false` — the app uses no
  encryption; LAN traffic is unencrypted local control data (see the project's
  ADR-0002 for the security model).

## Contact

- Demo/support contact: maxatovdias@gmail.com
