# ADR-0001: Local-Network, No-Cloud Topology with Mac as Source of Truth

> type: adr
> status: draft
> date: 2026-06-18
> deciders: []

---

## Context

Fiple connects an iPhone (remote) and a Mac (executor). We must decide the
connection topology and where authoritative state lives. The BRD mandates no
accounts, no passwords, no cloud, and no list of nearby devices — just a code.
Two questions are architecturally material: (1) does traffic stay on the LAN or
go through a cloud relay, and (2) does the phone or the Mac own tile state. These
choices shape transport, security model, persistence, and offline behavior, so
they are decided once here.

---

## Decision

1. **Local network only, no cloud.** Both devices must be on the same Wi-Fi.
   Discovery uses Bonjour/mDNS in the background; control uses a WebSocket over
   the LAN. No cloud relay, no account.
2. **Code-based pairing without a device list.** The Mac shows a 4-digit code and
   advertises its service; the phone discovers Macs silently and the code both
   selects and authenticates the target. Pairing is persisted on the phone for
   automatic reconnection until an explicit disconnect.
3. **Mac is the single source of truth.** Tiles are stored, managed, and executed
   only on the Mac. The phone holds no authoritative tile data — it renders
   snapshots and sends triggers.

---

## Alternatives Considered

| Option | Pros | Cons |
| --- | --- | --- |
| Cloud relay (works across networks) | Works off-LAN; no discovery needed | Requires hosting, accounts, security surface; contradicts BRD "no cloud" |
| Multipeer Connectivity (P2P, BT/Wi-Fi) | Works without shared Wi-Fi | Less predictable for a command channel; heavier; weaker for request/response |
| Phone as source of truth | Tiles visible offline on phone | Phone can't know installed apps; sync conflicts; against "phone = remote" |
| Both store + sync | Offline tile view both sides | Conflict resolution complexity not justified for MVP |

---

## Consequences

- **Easier:** no backend to build or pay for; simpler privacy story (nothing
  leaves the LAN); phone app stays thin (no editing, no persistence beyond the
  remembered Mac).
- **Harder / constrained:** no cross-network use in MVP (deferred); requires a
  background silent-discovery + code-matching implementation; the 4-digit code
  must be bound to a session key so off-network actors cannot brute-force it.
- **Locked in:** transport is Apple-native LAN tech; revisiting cross-network use
  later will require a new ADR (relay or NAT traversal).

---

## Acceptance

- [ ] Human accepted before implementation.
- [ ] Related OpenSpec change cites this ADR.
- [ ] Architecture docs updated after implementation evidence exists.
