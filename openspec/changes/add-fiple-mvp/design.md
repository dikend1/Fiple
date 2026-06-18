# Design: Add Fiple MVP

This change implements the MVP slice described in the BRD/PRDs/TRD. Full design
context lives in those documents; this note records implementation-shaping
decisions for the change itself.

## Topology

Per `adr/0001-local-network-topology.md`: local network only, no cloud, Mac as
source of truth. Bonjour for silent discovery, WebSocket for the message channel,
JSON messages.

## Module layout (proposed)

- `Shared` — `Tile`, `Action`, message types (Codable). Imported by both apps.
- `FipleMac` — menu-bar app: persistence, Bonjour advertiser, WebSocket server,
  pairing, executor, tile-management UI.
- `FipleiOS` — remote app: discovery client, code entry, grid renderer, trigger
  client, connection-state UI.

## Protocol messages

| Message | Direction | Payload |
| --- | --- | --- |
| `pair` | phone → Mac | `{ code }` → `{ ok, macId }` / `{ error }` |
| `tiles.snapshot` | Mac → phone | `{ tiles: [Tile] }` (on connect + on change) |
| `run` | phone → Mac | `{ tileId }` → `{ tileId, results: [{actionId, ok, error?}] }` |
| `connection.state` | local (phone) | `{ connected: Bool }` |

## Decisions deferred to implementation

- WebSocket library vs raw `NWConnection` (TRD open question).
- Persistence: Codable JSON file vs SwiftData (TRD open question).
- Exact handshake binding the 4-digit code to a session key (TRD/PRD open
  question).
