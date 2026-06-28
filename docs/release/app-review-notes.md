# App Review Notes — Fiple 1.0.0

> Paste the relevant parts into **App Store Connect → App Review Information →
> Notes**. Fiple ships as a Universal Purchase: iOS remote + macOS companion
> share bundle id `com.fiple.Fiple`. Submit both together so the reviewer can
> test end-to-end.

## What Fiple is

Fiple turns an iPhone into a remote control for a Mac on the **same Wi-Fi**. The
Mac companion app defines "tiles" (each launches apps / websites / Shortcuts) and
a "Fiple Bar" of quick actions; tapping a tile on the iPhone restores that
working context on the Mac. No account, no cloud, no servers — everything stays
on the local network.

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
- If a Mac for testing is unavailable, the iOS app's connection/pairing screens
  are reachable without a Mac; full tile functionality requires the paired Mac.

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

- **Data collection:** none. No tracking, no analytics, no accounts. Privacy
  manifests declare only local `UserDefaults` access (`CA92.1`).
- **Network:** local network only (Bonjour + TCP on the LAN). No external
  servers.
- **Encryption:** `ITSAppUsesNonExemptEncryption = false` — the app uses no
  encryption; LAN traffic is unencrypted local control data (see the project's
  ADR-0002 for the security model).

## Contact

- Demo/support contact: maxatovdias@gmail.com
