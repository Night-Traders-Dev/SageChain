# Orbit Blockchain Public API Documentation

**Version**: 1.0 (devnet)  
**Protocol**: Orbit v1  
**Base URL**: `http://localhost:8333`  
**Content-Type**: `application/json`

---

## Overview

The Orbit RPC/Explorer API provides programmatic access to the Orbit blockchain. All endpoints return JSON responses. The API is read-only except for `/tx` submission.

---

## Authentication

No authentication required for devnet. All endpoints are public.

---

## Error Format

```json
{
  "error": "error_code",
  "message": "Human-readable description"
}
```

Common error codes:
- `not_found` — Resource not found
- `invalid_params` — Invalid request parameters
- `invalid_tx` — Transaction validation failed
- `internal_error` — Server error

---

## Core Endpoints

### GET /status

Returns node status.

**Response:**
```json
{
  "height": 123,
  "tip_hash": "a5db8c9323d054e7d169c25a65ad2d09949b36c6939895d2685a4126a22436af",
  "finalized_height": 120,
  "pool_remaining": "99950000000000000",
  "network_id": "orbit-devnet"
}
```

### GET /network

Returns network information.

**Response:**
```json
{
  "network_id": "orbit-devnet",
  "peer_count": 0
}
```

### GET /blocks/latest

Returns the latest block.

**Response:** See Block Object below.

### GET /blocks/{height}

Returns block by height.

**Path Parameters:**
- `height` (integer) — Block height

**Response:** See Block Object below.

### GET /blocks/hash/{hash}

Returns block by hash.

**Path Parameters:**
- `hash` (string) — 64-char hex block hash

**Response:** See Block Object below.

### GET /tx/{txid}

Returns transaction by ID.

**Path Parameters:**
- `txid` (string) — Transaction ID

**Response:** See Transaction Object below.

### GET /address/{address}

Returns account state.

**Path Parameters:**
- `address` (string) — orb-prefixed address (43 chars)

**Response:**
```json
{
  "address": "orb6c7cefb46b16de8a445108cb6f592f1823bfb468",
  "balance": "10000000000",
  "nonce": 5,
  "locked_balance": "5000000000",
  "activity_marker": 5000
}
```

### GET /validators

Returns list of all validators.

**Response:**
```json
[
  {
    "address": "orb...",
    "public_key": [...],
    "activation_height": 1,
    "uptime_score": 1000000,
    "trust_score": 1000000,
    "valid_vote_count": 120,
    "invalid_vote_count": 0,
    "status": "active"
  }
]
```

### GET /validators/{id}

Returns validator details.

**Path Parameters:**
- `id` (string) — Validator address

**Response:** See Validator Object above.

### GET /mining/rate

Returns current mining rate.

**Response:**
```json
{
  "rate": "8240958",
  "pool_remaining": "99950000000000000"
}
```

### GET /supply

Returns supply information.

**Response:**
```json
{
  "total_supply": "10000000000000000000",
  "circulating_supply": "10000000000",
  "mining_pool_remaining": "99950000000000000"
}
```

### POST /tx

Submits a signed transaction.

**Request Body:**
```json
{
  "kind": "transfer",
  "sender": "orb6c7cefb46b16de8a445108cb6f592f1823bfb468",
  "recipient": "orb6c7cefb46b16de8a445108cb6f592f1823bfb468",
  "amount": "1000000",
  "fee": "1000",
  "nonce": 5,
  "timestamp": 5000,
  "signature": [...],
  "tx_id": "a5db8c93...",
  "memo": "optional"
}
```

**Response:**
```json
{
  "tx_id": "a5db8c93...",
  "status": "pending"
}
```

---

## Explorer Endpoints

### GET /explorer/blocks

Paginated block list (newest first).

**Query Parameters:**
- `page` (integer, default: 0) — Page number
- `limit` (integer, default: 20) — Items per page (max 100)

**Response:**
```json
{
  "blocks": [
    {
      "height": 123,
      "hash": "a5db8c93...",
      "timestamp": 61500,
      "proposer": "orb...",
      "tx_count": 2,
      "finalized": true
    }
  ],
  "page": 0,
  "limit": 20,
  "total": 124
}
```

### GET /explorer/txs

Paginated transaction list (newest first).

**Query Parameters:**
- `page` (integer, default: 0)
- `limit` (integer, default: 50, max 200)

**Response:**
```json
{
  "transactions": [
    {
      "tx_id": "a5db8c93...",
      "block_height": 123,
      "kind": "transfer",
      "sender": "orb...",
      "recipient": "orb...",
      "amount": "1000000",
      "fee": "1000",
      "timestamp": 61500
    }
  ],
  "page": 0,
  "limit": 50,
  "total": 1240
}
```

### GET /explorer/address/{address}

Returns address with recent transactions.

**Path Parameters:**
- `address` (string) — orb-prefixed address

**Response:**
```json
{
  "address": "orb6c7cefb46b16de8a445108cb6f592f1823bfb468",
  "balance": "10000000000",
  "nonce": 5,
  "locked_balance": "5000000000",
  "activity_marker": 5000,
  "recent_transactions": [
    {
      "tx_id": "a5db8c93...",
      "block_height": 123,
      "kind": "transfer",
      "sender": "orb...",
      "recipient": "orb...",
      "amount": "1000000",
      "fee": "1000",
      "direction": "out"
    }
  ]
}
```

### GET /explorer/validators

Returns all validators with full details.

**Response:**
```json
{
  "validators": [
    {
      "address": "orb...",
      "public_key": [...],
      "activation_height": 1,
      "last_seen_height": 123,
      "uptime_score": 1000000,
      "trust_score": 1000000,
      "valid_vote_count": 120,
      "invalid_vote_count": 0,
      "proposed_blocks": 10,
      "accepted_blocks": 10,
      "penalty_points": 0,
      "status": "active"
    }
  ]
}
```

### GET /explorer/mining/stats

Returns mining statistics.

**Response:**
```json
{
  "current_rate": "8240958",
  "pool_remaining": "99950000000000000",
  "pool_exhausted_pct": 0,
  "recent_rewards": [
    {
      "height": 123,
      "reward": "4120479000",
      "mining_context": {
        "users": 10000,
        "height": 123,
        "score_scaled": 500000,
        "eligible_seconds": 500
      }
    }
  ]
}
```

### GET /explorer/network/health

Returns network health metrics.

**Response:**
```json
{
  "height": 123,
  "finalized_height": 120,
  "finality_lag": 3,
  "validator_count": 3,
  "peer_count": 0,
  "pool_remaining": "99950000000000000"
}
```

---

## Data Types

### Block Object

```json
{
  "hash": "a5db8c9323d054e7d169c25a65ad2d09949b36c6939895d2685a4126a22436af",
  "height": 123,
  "previous_hash": "prev...",
  "state_root": "6373642edb...",
  "tx_root": "e572967d66...",
  "validator_root": "249e8a947b...",
  "proposer": "orb6c7cefb46b16de8a445108cb6f592f1823bfb468",
  "timestamp": 61500,
  "protocol_id": 1,
  "proof": {
    "users": 10000,
    "height": 123,
    "score_scaled": 500000,
    "eligible_seconds": 500
  },
  "transactions": [Transaction Object]
}
```

### Transaction Object

```json
{
  "tx_id": "a5db8c93...",
  "kind": "transfer|reward|lock|unlock|claim",
  "sender": "orb...",
  "recipient": "orb...",
  "amount": "1000000",
  "fee": "1000",
  "nonce": 5,
  "timestamp": 61500,
  "memo": "optional memo",
  "signature": [...],
  "public_key": [...]
}
```

**Reward transaction additional fields:**
```json
{
  "mining": {
    "users": 10000,
    "height": 123,
    "score_scaled": 500000,
    "eligible_seconds": 500
  }
}
```

**Lockup transaction additional fields:**
```json
{
  "lock_duration": 100,
  "claim_height": 1100,
  "lockup_id": "lockup-1"
}
```

### Validator Object

```json
{
  "address": "orb...",
  "public_key": [...],
  "activation_height": 1,
  "last_seen_height": 123,
  "uptime_score": 1000000,
  "trust_score": 1000000,
  "valid_vote_count": 120,
  "invalid_vote_count": 0,
  "proposed_blocks": 10,
  "accepted_blocks": 10,
  "penalty_points": 0,
  "status": "active|pending|slashed"
}
```

---

## Address Format

`orb` + 40 lowercase hex characters (43 total).

Example: `orb6c7cefb46b16de8a445108cb6f592f1823bfb468`

Derived from: `orb` + first 40 chars of SHA256(canonical(Lamport public key))

---

## Amounts

All amounts are **base units** as strings.
1 ORBIT = 100,000,000 base units (10^8)

Example: 100 ORBIT = "10000000000"

---

## Signatures (devnet)

Lamport one-time signatures over SHA-256.
- 64-leaf public key (32 pairs × 2)
- 32 revealed preimages per signature
- ONE-TIME USE: never reuse a seed for two signatures

---

## Rate Limits

No rate limits in devnet. Production will enforce limits.

---

## WebSocket (Future)

Real-time block/transaction notifications planned for Phase 10+.

---

## Examples

### Check balance
```bash
curl http://localhost:8333/address/orb6c7cefb46b16de8a445108cb6f592f1823bfb468
```

### Submit transaction
```bash
curl -X POST http://localhost:8333/tx \
  -H "Content-Type: application/json" \
  -d '{"kind":"transfer","sender":"orb...","recipient":"orb...","amount":"1000000","fee":"1000","nonce":5,"timestamp":5000,"signature":[...],"tx_id":"..."}'
```

### Get latest blocks
```bash
curl "http://localhost:8333/explorer/blocks?page=0&limit=10"
```

---

## Changelog

- v1.0: Initial devnet API (Phases 1-9)