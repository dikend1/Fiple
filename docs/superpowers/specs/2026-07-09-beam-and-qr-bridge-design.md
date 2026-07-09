# Beam (phone → Mac files) + QR/Text Bridge — Design

Date: 2026-07-09 · Status: approved in chat · Branch: `feat/remote-terminal`

## Goal

1. **Beam**: send a photo/video/file from the iPhone to the Mac's ~/Downloads
   over the existing LAN channel (AirDrop-lite, no AirDrop needed).
2. **QR/Text bridge**: scan a QR code or live text with the phone camera and
   put the recognized text straight onto the Mac's clipboard, ready to ⌘V.

## Wire (ClientMessage, existing tile channel)

Frames cap at 8 MB and `Data` rides as base64 (+33%), so files transfer in
chunks:

- `beamBegin(transferID: UUID, name: String, totalBytes: Int64)`
- `beamChunk(transferID: UUID, bytes: Data)` — ~1 MB per chunk
- `beamEnd(transferID: UUID)`
- `setClipboard(text: String)` — the QR/text bridge (and a "paste text on the
  Mac" affordance in the same sheet)

ServerMessage:

- `beamResult(transferID: UUID, ok: Bool, message: String?)` — sent on
  `beamEnd` (success/failure) or mid-transfer on a fatal error.

All handled only from the authenticated peer, like every other message.

## Mac

- `BeamReceiver` (FipleKit, macOS): assembles chunks into a temp file
  (streaming to disk, not RAM), on `beamEnd` moves it into ~/Downloads.
  File name sanitized (strip path separators / leading dots); collisions get
  "name (2).ext". One transfer at a time; 500 MB cap; an unfinished transfer
  is discarded on disconnect or a new `beamBegin`.
- Local notification "«IMG_1234.heic» received from iPhone" on completion.
- `setClipboard` → `NSPasteboard.general` (clearContents + setString).
- Sandbox note: this branch runs unsandboxed (terminal); the MAS build needs
  `com.apple.security.files.downloads.read-write` — record in the openspec
  change when this ships.

## iOS

- Home gains a **"Send to Mac"** row (with Terminal / Smart Trash): sheet with
  PhotosPicker, a file importer, and a text field ("paste on your Mac") →
  chunked upload with a progress bar → checkmark / error toast.
- Home gains a **"Scan to Mac"** row: VisionKit `DataScannerViewController`
  (QR + live text); recognized item shows a "Send to Mac clipboard" button →
  haptic confirm. Requires `NSCameraUsageDescription`.
- Both rows appear only while connected.

## Limits (v1, deliberate)

One transfer at a time; 500 MB cap; no Mac→phone direction; no background
transfer (screen stays on); no multi-file batches (pick again).

## Testing

- FipleKit: codec round-trips for all new cases; `BeamReceiver` unit tests
  (chunk assembly, name sanitizing, collision suffixing, unknown transferID,
  over-cap rejection).
- Manual: photo → Downloads; 100 MB video; QR → ⌘V on the Mac.
