# ADR-0004: Off-LAN File Access via CloudKit

> type: adr
> status: draft
> date: 2026-07-01
> deciders: []

---

## Context

ADR-0001 fixed a local-network, no-cloud topology; ADR-0002 ratified a plaintext
LAN transport for the MVP and named explicit **criteria to revisit** it —
including (#1) usage beyond a trusted personal LAN and (#3) any cross-network /
relay / NAT-traversal feature, which "needs a new ADR regardless."

We now want a feature that fires both criteria: **pull a recent file off the Mac
to the phone from anywhere** (the "forgot my laptop at home" case), working even
when the Mac is asleep or off. The LAN transport cannot serve this — the devices
are on different networks — and a self-hosted relay/TURN server would contradict
the no-backend posture and add operational cost, accounts, and a new attack
surface.

This ADR decides the transport and trust model for that feature. It **extends**
ADR-0002 (which continues to govern the in-LAN remote-control channel); it does
not repeal it. Scope is bounded by the design doc
`docs/superpowers/specs/2026-07-01-remote-file-access-design.md`: read-only
download of a **bounded cache of recent files** from the standard folders.

## Decision

Adopt **CloudKit (private database) as the transport** for off-LAN file access:

1. **Transport: CloudKit private database**, one shared container across the
   macOS and iOS apps (e.g. `iCloud.com.fiple.app`). Records and file assets are
   written to `CKContainer.privateCloudDatabase`, encrypted by Apple in transit
   and at rest. No self-hosted server, no relay/TURN, no Fiple accounts.
2. **Identity = the device's existing Apple ID.** There is no in-app login. The
   private DB is automatically scoped to the iCloud account signed in on each
   device; the Mac and iPhone interoperate because they are the **same Apple ID**.
   Different IDs (or iCloud off) → the feature is unavailable and says so.
3. **Pre-uploaded bounded cache, not a full mirror.** The Mac keeps only a
   budgeted set of *recent* files from Desktop / Documents / Downloads in the
   private DB (defaults: ≤ 30 days, ≤ 200 files, ≤ 2 GB total, ≤ 100 MB/file),
   plus a separate pinned-favorites budget (≤ 50 files / 1 GB). Over-budget cache
   copies are evicted oldest-first.
4. **Read-only over the Mac filesystem (safety invariant).** The Mac agent only
   *reads* originals to produce cache copies. No feature path (eviction, disable,
   error) ever deletes or modifies files on the Mac disk — deletion touches only
   CloudKit cache copies. The phone only browses and downloads; it never writes
   back.
5. **Per-feature master switch.** The Mac exposes one toggle; turning it off
   purges the entire CloudKit cache (originals untouched).

This is accepted for a threat model of **a personal Apple ID the user controls**,
no shared credentials.

## Alternatives Considered

| Option | Pros | Cons |
| --- | --- | --- |
| **CloudKit private DB (chosen)** | No server/accounts; Apple-encrypted; scoped to user's Apple ID; works when Mac is off (pre-upload) | Requires same Apple ID + iCloud on both; consumes user's iCloud quota; some latency for large assets |
| **Self-hosted relay / TURN + WebSocket** | Full control; not tied to Apple ID | Backend to run + secure; accounts/auth to build; ongoing cost; contradicts no-backend policy |
| **On-demand pull only (Mac must wake via push)** | No pre-stored copies; smallest cloud footprint | Fails the core case: a sleeping/off Mac can't respond; closed-lid MacBook won't reliably wake |
| **Full mirror of standard folders to iCloud Drive** | Everything always available | Can exhaust iCloud quota; largely duplicates Apple's "Desktop & Documents in iCloud Drive"; weak differentiation |

## Consequences

- **Easier:** off-LAN access with zero server infrastructure; encryption and
  identity handled by Apple; the plaintext concern of ADR-0002 does not apply on
  this channel (different transport).
- **Constrained / accepted:**
  - Requires the **same Apple ID + iCloud enabled** on both devices; otherwise
    unavailable.
  - Consumes the user's **iCloud storage quota**; mitigated by the bounded cache
    and eviction. Quota-full is a surfaced error, not a silent failure.
  - **Latency:** large assets take time to upload (Mac) and download (phone).
  - **Freshness gap:** an *old* file not in the cache is unreachable while the
    Mac is off — an accepted trade of variant A (recent-files cache).
  - Adding a new persisted store means a **privacy-manifest / data-collection
    review** and App Store data-use disclosure (iCloud private DB is user-owned
    data, but must be declared).
- **Relationship to ADR-0002:** unchanged for the LAN channel. This ADR resolves
  ADR-0002 criteria #1 and #3 for the file-access feature specifically; it does
  **not** move the LAN control channel to a new transport.

## Acceptance

- [ ] Human accepted before implementation.
- [ ] Related OpenSpec change (`add-remote-file-access`) cites this ADR.
- [ ] PRD `prd/fiple-remote-file-access.md` cross-referenced.
- [ ] Architecture docs updated after implementation evidence exists.
- [ ] Privacy manifest / App Store data-use disclosure reviewed for the CloudKit
      store.
