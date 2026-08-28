# MINING — Dynamic Mining Rate Specification

Status: draft (Phase 0 freeze pending)

## Canonical formula (§7)

    R = R_base * UserFactor * SupplyFactor * TimeDecay * NodeBoost

    UserFactor   = (U_target / max(U, U_target)) ^ 0.5
    SupplyFactor = S / S_max            # S = REMAINING mining supply
    TimeDecay    = 0.5 ^ (B / B_halflife)
    NodeBoost    = 1 + min(Score, 0.10)

> Spec correction (§7.1): v1 MUST use `S / S_max`. The historical
> `1 - S/S_max` variant is rejected — it rewards depletion instead of
> tapering and contradicts the worked examples.

## Parameters (§8, consensus-critical)

    R_base       = 0.082 ORBIT/sec
    U_target     = 10,000 active users
    S_max        = 1,000,000,000 ORBIT
    B_halflife   = 100,000 blocks
    NodeBoostMax = 0.10

## Pinned v1 implementation rules (orbit/mining/rate.sage)

- **Fixed-point grid:** SCALE = 10^6 for every factor; final division by
  SCALE^4 in a single step. All arithmetic via decimal-string bigints
  (`orbit/core/bigint.sage`) — doubles never touch consensus values.
- **R_base** = 8,200,000 base-units/sec (exact integer form of 0.082 ORBIT).
- **TimeDecay (§11 option 3 — pinned integer rule):**
  `h = B div H; f = B mod H; base = floor(SCALE / 2^h); next = floor(base/2);
  TD = base - floor((base - next) * f / H)`.
  Exact at half-life boundaries (TD(H) = 0.5); linear interpolation between;
  underflows to zero past h=20 on this grid.
- **NodeBoost clamp:** scores arrive on a 10^6 grid where 10^6 == 1.00;
  boost = min(score, 100000) on that same grid → max multiplier 1.10.
- **Invalid inputs raise** (negative users/score/supply, S > S_max,
  H <= 0) — malformed consensus state is rejected, never normalized.

## Accounting rules

- Integer base units everywhere; floor() rounding after all factors multiply (§6)
- `reward <= remaining_supply`; exhaustion pins reward to remaining then stops (§10)
- TimeDecay indexes on block height, never wall-clock time (§11)
- Test vectors: plan §39; edge cases: §40
