# Fiple

**Turn your iPhone into a remote control for your Mac — one tap to restore your working context.**

Fiple is a pair of native Swift apps (macOS menu-bar companion + iOS remote) that let you launch apps, open URLs, run terminal commands, and clean up your Mac — all from your iPhone. No backend, no accounts. Everything runs over your local network with end-to-end encryption on sensitive channels.

---

## Features

### Core

- **Workspace presets** — define tiles on the Mac that launch one or more actions (open apps, websites, files). A tile with several actions restores your full working context in one tap.
- **Fiple Bar** — curated quick-launch strip pinned to the top of both apps. One tap fires a single action. Curated on the Mac, triggered from the iPhone.
- **iPhone remote** — silently discovers your Mac via Bonjour, pairs with a 4-digit code, and shows your tiles. Tap any tile to trigger it on the Mac. Session token in the Keychain for silent reconnection.
- **Secure pairing** — brute-force protection (5 wrong codes = 30 s lockout + code rotation), server-authoritative execution (phone sends only IDs, Mac resolves and validates actions), URL allowlist blocks dangerous schemes.

### Terminal (Fiple Pro)

- **Encrypted remote shell** — full terminal access to your Mac from your iPhone via TLS-PSK encrypted channel. Master password + pairing token two-factor auth.
- **Multiple sessions** — up to 5 parallel shell tabs on the phone (1 on free tier). Tab persistence with unseen-output indicators.
- **Session persistence** — shell survives phone disconnect. Background and reconnect to resume the same session with scrollback replay.
- **Full keyboard** — Esc, Tab, ^C, arrows, paste toolbar. Pinch-to-zoom. SwiftTerm xterm-compatible renderer.
- **Master password** — never stored on the Mac (only PBKDF2-HMAC-SHA256 salted verifier). Phone stores in Keychain with Face ID.

### Smart Trash (Fiple Pro)

- **Auto-detect stale files** — Mac scans Desktop, Documents, and Downloads for files untouched for 15-90 days (configurable). Uses Spotlight's last-used-date.
- **iPhone swipe review** — photo-cleaner-style swipe deck. Swipe left to stage for trashing, right to keep forever. Undo supported.
- **In-app basket** — review staged files with thumbnails, see total reclaimable size. Commit empties to macOS Trash (recoverable).
- **Auto-enforcement** — Mac moves past-deadline candidates to Trash automatically at launch and daily.
- **iOS notifications** — reminders 2 days, 1 day, then every 3 hours before auto-trash deadlines.
- **Permanent keep-list** — files you keep are never proposed again.

### Beam (Send to Mac)

- **Send photos & files** — pick photos/videos (PhotosPicker) or any files from your iPhone, beam them to your Mac's Downloads folder.
- **Multi-select** — send batches of up to 30 items with progress tracking ("Sending 2 of 5").
- **Clipboard too** — images are also copied to your Mac's clipboard.
- **500 MB per file** limit, collision-safe naming.

### Remote Gestures

- **2-finger swipe** — up/down on the iPhone screen triggers ⌘C/⌘V on the Mac's frontmost app (copy/paste).
- **4-finger swipe** — up/down enters/exits fullscreen on the Mac's focused window.
- Gestures work from any screen in the app.

### Share Extension

- **Share → Fiple** — from any iOS app, share files, text, or URLs directly to your Mac via the system share sheet. No need to open the app first.

### Fiple Pro

- **Unlimited workspaces** — free tier: 2 workspace presets and 8 Fiple Bar items. Pro unlocks unlimited.
- **Parallel terminal sessions** — free: 1 session. Pro: up to 5.
- **Monthly ($2.99) or Lifetime ($29.99)** — one purchase, all your devices.

### Mac App

- **Menu-bar app** — lives in the menu bar. Shows connection status, pairing code, quick access to management UI.
- **Self-installer** — moves itself to `/Applications` on first launch (non-MAS builds). Admin prompt if needed.
- **Launch at Login** — optional auto-start via SMAppService.
- **Three build postures** — Debug (sandbox off, terminal enabled), Release-MAS (sandboxed, App Store), Release-DevID (hardened runtime, site download, terminal enabled).

---

## Architecture

Three Swift modules, no backend, no accounts:

| Module | Platform | Role |
| --- | --- | --- |
| **FipleKit** | macOS + iOS | Pure, tested core: models, wire protocol, transport, pairing, terminal, trash engine, beam receiver, entitlements, logging, security (PBKDF2, TLS-PSK, Keychain). |
| **FipleMac** | macOS | Source of truth + executor: Bonjour advertising, pair/token handshake, NSWorkspace actions, terminal service (forkpty), trash scanner, FSEvents watcher, self-installer, gesture executor |
| **FipleiOS** | iOS | Remote control: silent Bonjour discovery, swipe-deck trash review, terminal client (SwiftTerm), photo/file beam, gesture overlay, paywall, onboarding. |
| **FipleShare** | iOS | Share extension — beam files/text/URLs to Mac from any app. |

**Transport:** Bonjour `_fiple._tcp` + NWConnection/NWListener. Plaintext TCP for tile channel (LAN trust model, ADR-0002). TLS 1.2 PSK with AES-128-GCM for terminal channel (ADR-0005).

**88+ unit and integration tests** across model coding, framing, pairing, transport, terminal auth, trash engine, and real-Bonjour loopback.

---

## Quick Start

### Prerequisites

- Xcode 16+ (Swift 6.0+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

### Setup

```bash
# Generate the Xcode project
xcodegen generate

# Run core tests
cd FipleKit && swift test

# Build both targets
xcodebuild -project Fiple.xcodeproj -scheme FipleMac -destination 'platform=macOS' build
xcodebuild -project Fiple.xcodeproj -scheme FipleiOS -destination 'generic/platform=iOS Simulator' build
```

### Run

1. Launch **FipleMac** — it lives in the menu bar and starts advertising over Bonjour.
2. Launch **FipleiOS** on a device on the same Wi-Fi — it discovers the Mac automatically.
3. Enter the 4-digit code shown on the Mac.
4. Create tiles and a Fiple Bar on the Mac, then tap them from your iPhone.

---

## Project Structure

```
Fiple/
├── FipleKit/                # Shared Swift package (Swift 6)
│   ├── Sources/FipleKit/
│   │   ├── AppInfo/         # Product URLs, favicon helpers
│   │   ├── Beam/            # File transfer receiver (Mac)
│   │   ├── Entitlement/     # Free-tier gating
│   │   ├── Execution/       # Tile runner, action executor
│   │   ├── Logging/         # os_log subsystem
│   │   ├── Model/           # Tile, Action, RunRecord, etc.
│   │   ├── Pairing/         # PairingCode, PairingThrottle
│   │   ├── Security/        # Keychain, ActionPolicy, MasterPassword
│   │   ├── Terminal/        # PTY session, TLS-PSK, auth, scrollback
│   │   ├── Transport/       # PeerConnection, FipleServer, FipleClient
│   │   ├── Trash/           # StaleFileScanner, review session, deadlines
│   │   └── Wire/            # FrameCodec, MessageCodec, messages
│   └── Tests/               # 88+ unit + integration tests
├── Apps/
│   ├── FipleMac/            # macOS menu-bar companion
│   │   ├── Stores/          # TileStore, PinnedAppsStore, RecentStore
│   │   ├── Views/           # Workspaces, Terminal, Trash, Settings, Sidebar
│   │   └── ...              # ServerController, TerminalController, TrashController
│   ├── FipleiOS/            # iOS remote app
│   │   ├── Views/           # Home, Terminal, Trash, Beam, Paywall, Onboarding, Tools
│   │   └── ...              # RemoteController, GestureOverlay
│   └── FipleShare/          # iOS share extension
├── docs/
│   ├── architecture/        # Current implemented truth
│   └── design-docs/         # BRD, PRD, TRD, ADR (intent/target contracts)
├── openspec/                # Spec-driven development
│   ├── changes/             # Active + archived OpenSpec changes
│   └── specs/               # Implemented capabilities
├── project.yml              # XcodeGen project definition
└── AGENTS.md                # Agent operating rules
```

---

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI |
| Transport | Bonjour + Network.framework (TCP), TLS 1.2 PSK (terminal) |
| Wire format | JSON + 4-byte length prefix |
| Terminal renderer | SwiftTerm (MIT) |
| Subscriptions | RevenueCat (StoreKit 2) |
| Persistence | JSON files (Mac), Keychain + UserDefaults |
| Cloud | CloudKit private database (off-LAN files, branch) |
| Build | XcodeGen (project.yml) |

---

## Security

- **No TLS on tile channel** — trust model assumes local network is trusted (ADR-0002).
- **TLS 1.2 PSK with AES-128-GCM** for the terminal channel, keyed from the pairing token (ADR-0005).
- **Two-factor terminal auth** — pairing token + master password PBKDF2 proof.
- **URL allowlist** — remote can only trigger http/https URLs.
- **Pairing throttle** — 5 wrong attempts → 30 s lockout + code rotation.
- **Session tokens** in the Keychain, not UserDefaults.
- **Server-authoritative execution** — Mac resolves IDs against saved tiles.
- **Master password** never stored on Mac — only a salted PBKDF2 verifier.
- **Constant-time comparisons** for passwords and tokens.

---

## Privacy

- **No data collected.** No tracking, no analytics, no telemetry, no servers.
- Tile traffic never leaves the LAN.
- Terminal data is encrypted with TLS-PSK — not readable on the network.
- File data goes only to the user's own CloudKit private database (off-LAN).
- Privacy manifests declare only `NSPrivacyAccessedAPICategoryUserDefaults` (reason CA92.1).

---

## Build Postures

The Mac app has three build configurations for different distribution channels:

| Config | Sandbox | Terminal | Use case |
| --- | --- | --- | --- |
| **Debug** | Off | Enabled | Local development |
| **Release-MAS** | On | Disabled | Mac App Store |
| **Release-DevID** | Off | Enabled | Developer ID / site download |

---

## Tests

```bash
cd FipleKit && swift test
```

Covers: model coding, frame codec (send/receive caps, pre-auth limit), wire forward-compatibility, pairing code + throttle/lockout, ActionPolicy URL allowlist, ActionLookup id resolution, tile-run semantics, real-socket loopback, connection limits + auth-timeout, discovery dedupe + real-Bonjour, remote-files engine (budgets, eviction, pinning), terminal auth (PBKDF2, TLS-PSK derivation), trash engine (scanner, deadlines, review session), and beam/file transfer.

---

## License

All rights reserved. This project is not open-source software.