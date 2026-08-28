# TOKENOMICS — Supply, Allocations, Lockups

Status: draft

## Supply (§6)

TOTAL_SUPPLY = 100,000,000,000 ORBIT

| Wallet | Allocation (ORBIT) | % |
|---|---:|---:|
| system | 81,900,000,000 | 81.90 |
| lockup_rewards | 100,000,000 | 0.10 |
| mining | 1,000,000,000 | 1.00 |
| nodefeecollector | 0 | 0.00 |
| community | 3,000,000,000 | 3.00 |
| team | 5,000,000,000 | 5.00 |
| airdrop | 1,000,000,000 | 1.00 |
| foundation | 2,000,000,000 | 2.00 |
| partnerships | 1,000,000,000 | 1.00 |
| reserve | 5,000,000,000 | 5.00 |

Genesis must sum exactly to TOTAL_SUPPLY — enforced by
`orbit/core/genesis.sage: validate_allocations()`.

## Mining pool

1,000,000,000 ORBIT, depleted only by reward transactions (§10).

## Lockups (§18)

Target ~5% APR represented as an explicit per-block/per-epoch protocol
parameter with deterministic accounting — never an informal wall-clock APR.
State machine: UNLOCKED → LOCKED → CLAIMABLE → LOCKED/UNLOCKED.
