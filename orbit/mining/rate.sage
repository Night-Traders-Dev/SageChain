# orbit/mining/rate.sage — dynamic mining-rate math (plan §7, §13)
# Orbit Blockchain | Protocol v1 | Status: implemented (fixed-point v1)
#
# Canonical formula with the §7.1 correction (SupplyFactor = S/S_max):
#   R [base-units/sec] = R_BASE_UNITS * UF * SF * TD * NB / SCALE^4
#
# All factors are scaled integers (SCALE = 10^6); multiplication and division
# run through bigint strings so nothing ever touches floating point.
#
# TimeDecay pinned algorithm (§11 option 3 — fully specified integer rule):
#   h = B div H ; f = B mod H
#   base  = floor(SCALE / 2^h)          (exact halvings, floor at each step)
#   next  = floor(base / 2)
#   TD    = base - floor((base - next) * f / H)
# Monotonic non-increasing; TD(B=H)=SCALE/2 exactly; TD reaches 0 when
# SCALE/2^h underflows to 0 (h > 20 with SCALE=10^6), i.e. pool effectively
# dormant long before exhaustion — documented protocol behavior.

import orbit.core.bigint as bi

let PROTOCOL_ID = 1

let SCALE_N = 1000000                       # fixed-point scale as an integer
let SCALE = "1000000"                       # ...and as a string
let SCALE4 = bi.bi_mul(bi.bi_mul(SCALE, SCALE), bi.bi_mul(SCALE, SCALE))

let R_BASE_UNITS = "8200000"                # 0.082 ORBIT/sec in base units
let U_TARGET = 10000
let S_MAX_UNITS = bi.bi_mul("1000000000", "100000000")   # 1e17
let B_HALFLIFE = 100000
let NODE_BOOST_MAX_SCALED = 100000          # 0.10 * SCALE
let SCORE_SCALE = 1000000                   # node scores arrive on this scale

# UserFactor scaled: floor(SCALE * U_target / max(U, U_target))
proc user_factor_scaled(users):
    var u = users
    if u < 0:
        raise "mining: negative active-user count"
    if u < U_TARGET:
        u = U_TARGET
    let qr = bi.bi_divmod(bi.bi_mul(bi.bi_from_number(U_TARGET), SCALE),
                          bi.bi_from_number(u))
    return bi.bi_to_number(qr[0])

# SupplyFactor scaled: floor(SCALE * S / S_max); S > S_max rejected (§40)
proc supply_factor_scaled(remaining_supply):
    let s = remaining_supply
    if bi.bi_cmp(s, "0") < 0:
        raise "mining: negative remaining supply"
    if bi.bi_cmp(s, S_MAX_UNITS) > 0:
        raise "mining: remaining supply exceeds S_max"
    let qr = bi.bi_divmod(bi.bi_mul(s, SCALE), S_MAX_UNITS)
    return bi.bi_to_number(qr[0])

proc time_decay_scaled(block_height, half_life):
    if half_life <= 0:
        raise "mining: half_life must be positive"
    if block_height < 0:
        raise "mining: negative block height"
    let h = int(block_height / half_life)
    let f = block_height % half_life
    var base = SCALE_N
    var i = 0
    while i < h:
        base = int(base / 2)
        if base == 0:
            return 0
        i = i + 1
    let nxt = int(base / 2)
    return base - int((base - nxt) * f / half_life)

# NodeBoost scaled: SCALE + min(score_on_SCORE_SCALE, NODE_BOOST_MAX_SCALED*10)
# Scores arrive on SCORE_SCALE (1e6). Clamp to [0, 1.0] then cap boost at 10%.
proc node_boost_scaled(score_scaled):
    # Score arrives on SCORE_SCALE where 10^6 == 1.00. Boost contributes up
    # to NODE_BOOST_MAX_SCALED (10%) ON THE SCALE GRID — hard-capped (§12).
    var s = score_scaled
    if s < 0:
        raise "mining: negative node score"
    if s > SCORE_SCALE:
        s = SCORE_SCALE
    # Score and fixed-point grids are BOTH 10^6, so the boost contribution
    # is just the clamped score — hard-capped at +10% (plan §12).
    var boost = s
    if boost > NODE_BOOST_MAX_SCALED:
        boost = NODE_BOOST_MAX_SCALED
    return SCALE_N + boost

proc calculate_mining_rate(users, remaining_supply, block_height, score_scaled):
    # Returns bigint-string rate in base units per second.
    let uf = user_factor_scaled(users)
    if uf == 0:
        return "0"
    let sf = supply_factor_scaled(remaining_supply)
    if sf == 0:
        return "0"
    let td = time_decay_scaled(block_height, B_HALFLIFE)
    if td == 0:
        return "0"
    let nb = node_boost_scaled(score_scaled)

    let num = bi.bi_mul(R_BASE_UNITS, bi.bi_from_number(uf))
    let num2 = bi.bi_mul(num, bi.bi_from_number(sf))
    let num3 = bi.bi_mul(num2, bi.bi_from_number(td))
    let num4 = bi.bi_mul(num3, bi.bi_from_number(nb))
    let qr = bi.bi_divmod(num4, SCALE4)
    return qr[0]
