# CONSENSUS — Proof of Insight (PoI)

Status: draft (Phase 4)

## Roles (§15)

proposer · validator · voter · observer/full node

## Flow

Validator selected as proposer → builds candidate block → broadcast proposal →
independent validation → signed votes → PoI-weighted tally → finality
threshold → block finalized.

## Pinned v1 rules (orbit/consensus/*, sage-c reference implementation)

**Registration.** Minimum self-stake 1,000 ORBIT moved balance →
locked_balance; below minimum a validator registers as `pending` with zero
weight. One registration per address.

**Scores.** Grid 10^6 (1.0 = 10^6). Initial trust 0.25 (bounded start);
valid vote +0.002; invalid act −0.05 and +50,000 penalty points; at
600,000 penalty points the validator is slashed (weight → 0). Uptime is an
integer EMA (`up += (target−up)/100`) over per-height presence.
Accrual applies at most once per height — no burst jumps.

**Vote weight.**

    weight = floor(BASE * trust * uptime / 10^12)      BASE = 10^6

**Votes.** Each vote is Lamport-signed over canonical fields
(validator_addr, block_hash, height, choice) and must commit to the
validator's registered `orb…` address. Duplicates by (addr, hash) are
dropped and reported.

**Finality.** Integer-pinned 2/3 rule — no division:

    3 * yes_weight >= 2 * total_weight

Zero-weight rounds never finalize. A FinalityCertificate
{height, block_hash, yes, total, voter_count} re-derives deterministically
from stored votes.

**Immutability (§27).** `Chain.append_block` rejects any block whose parent
height is below `finalized_height`.

> Devnet crypto note: votes use the one-time Lamport scheme; validators
> rotate seeds per vote. ed25519 replaces this before testnet (§24).

## Separation rule

Mining eligibility (rewards) and finality authority (voting weight) are
deliberately independent mechanisms (§15).

## Finality

Once finalized under the protocol threshold, blocks are immutable absent an
explicit recovery mechanism (§27).
