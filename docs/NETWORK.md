# NETWORK — P2P Protocol

Status: draft (Phase 5)

## Envelope (§25)

Every message carries: `protocol_version`, `message_type`, `network_id`,
`sender_id`, `sequence`, `payload`, `signature`.

## Message types

HELLO PEER_LIST GET_BLOCK BLOCK GET_BLOCKS BLOCKS GET_TX TX VOTE PROPOSAL
FINALITY STATE_REQUEST STATE_RESPONSE PING PONG

## Gossip rules

Reject duplicate IDs · cap sizes · rate-limit peers · penalize invalid
messages · no unbounded allocations.

## Sync (§26)

Load local state → verify chain → connect → exchange heights/finality →
request missing blocks → validate each → commit. Longest chain alone is
never sufficient; PoI finality decides.
