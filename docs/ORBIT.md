# ORBIT — Technical Protocol Overview

Status: draft (Phase 0)

## Identity

- Chain/network IDs: `orbit-devnet`, `orbit-testnet`, `orbit-mainnet` (§29)
- Protocol version: `1` — carried by every block (§48)
- Decimals: 8 (1 ORBIT = 10^8 base units, §6)

## Design pillars

1. Deterministic state machine first (§54)
2. Consensus-critical math in integer/fixed-point only (§5, §6)
3. Narrow crypto interface: hash / keypair / sign / verify (§24)
4. Storage behind an interface; JSON in v1, binary later (§28)

## Implemented foundations (v0.1)

- Canonical serialization: `orbit/crypto/encoding.sage`
  (`nil`→n · bool→b0/b1 · int→i…e · string→s<len>: · array→l…e ·
  dict→d…e with lexicographically sorted keys; fractional floats and
  ints ≥ 2^53 rejected)
- Amounts are **decimal-string bigints** (`orbit/core/bigint.sage`) because
  Sage numbers are doubles (exact < 2^53) while supply is 1e19 base units.
- Addresses: `orb` + 40 lowercase hex chars (43 total), derived from the
  canonical hash of a Lamport public key (`orbit/wallet/account.sage`).
- Signatures: Lamport one-time over SHA-256 — publicly verifiable, devnet
  scheme; one keypair MUST sign one transaction until ed25519 lands (§24).
- Genesis: allocation table enforced with a bigint sum invariant; network ID
  is hashed into the genesis previous-hash so devnet/testnet/mainnet chains
  can never share a history.

## Open decisions (Phase 0 checklist, §44)

- [ ] Canonical serialization format
- [ ] Hash & signature algorithms pinned in genesis config
- [ ] Active-user semantics (§9)
- [ ] Node-score weighting (§12)
- [ ] PoI vote-weight formula (§15)
- [ ] Finality threshold (§27)
