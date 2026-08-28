# orbit/consensus/trust.sage — trust & uptime scoring (plan §12)
# Orbit Blockchain | Protocol v1 | Status: implemented (v1 rules)
#
# Grid: all scores on 10^6 where 10^6 == 1.00.
# Anti-gaming rules (§12), each pinned here:
#   - bounded initial score   : new validators start at INITIAL_TRUST (0.25)
#   - gradual changes         : valid-vote accrual is +TRUST_ACCRUAL per vote
#   - no burst jumps          : accrual applies at most once per height
#   - penalties outweigh      : PENALTY_STEP >> TRUST_ACCRUAL
#   - uptime is an integer EMA: up += (target - up) / UPTIME_EMA_DIV
#
# Truncation note: integer division truncates toward zero; the EMA handles
# the negative-diff case symmetrically so drift direction is explicit.

import orbit.consensus.validator as validatormod

let TRUST_ACCRUAL = 2000        # +0.002 per valid vote
let PENALTY_STEP = 50000        # -0.05 per invalid act
let UPTIME_EMA_DIV = 100
let MAX_SCORE = 1000000

proc clamp_score(v):
    if v < 0:
        return 0
    if v > MAX_SCORE:
        return MAX_SCORE
    return v

# Called once per height per validator with the height's observed outcome.
proc apply_vote_outcome(registry, addr, height, was_valid):
    if not registry.has(addr):
        return [false, "unknown_validator"]
    let v = registry.get(addr)
    if v["current_status"] != "active":
        return [false, "not_active"]
    # one accrual/penalty per height (no burst jumps)
    if v["last_seen_height"] == height:
        return [false, "already_scored"]

    if was_valid:
        v["trust_score"] = clamp_score(v["trust_score"] + TRUST_ACCRUAL)
        v["valid_vote_count"] = v["valid_vote_count"] + 1
    else:
        v["trust_score"] = clamp_score(v["trust_score"] - PENALTY_STEP)
        v["penalty_points"] = v["penalty_points"] + PENALTY_STEP
        v["invalid_vote_count"] = v["invalid_vote_count"] + 1
        if v["penalty_points"] >= validatormod.PENALTY_SLASH_LIMIT:
            registry.slash_or_deactivate(addr, height)
            return [true, "slashed"]

    v["last_seen_height"] = height
    return [true, nil]

# Uptime EMA over binary presence observations (seen: true/false)
proc apply_uptime_observation(registry, addr, seen):
    if not registry.has(addr):
        return [false, "unknown_validator"]
    let v = registry.get(addr)
    let target = 0
    if seen:
        target = MAX_SCORE
    let diff = target - v["uptime_score"]
    if diff >= 0:
        v["uptime_score"] = clamp_score(v["uptime_score"] + int(diff / UPTIME_EMA_DIV))
    else:
        v["uptime_score"] = clamp_score(v["uptime_score"] - int((-diff) / UPTIME_EMA_DIV))
    return [true, nil]
