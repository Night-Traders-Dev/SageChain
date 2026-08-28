# orbit/mining/rewards.sage — reward issuance + pool accounting (plan §10)
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.core.bigint as bi
import orbit.mining.rate as rate

# rate: bigint-string base-units/sec; remaining_supply: bigint string.
# Invariant enforced by caller too: reward <= remaining (§38 reward conservation).
proc calculate_block_reward(mining_rate, eligible_seconds, remaining_supply):
    if eligible_seconds < 0:
        raise "rewards: negative eligible seconds"
    let total = bi.bi_mul(mining_rate, bi.bi_from_number(eligible_seconds))
    if bi.bi_cmp(total, remaining_supply) > 0:
        return remaining_supply   # pool exhaustion pins reward to remainder (§10)
    return total
