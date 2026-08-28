# orbit/core/genesis.sage — deterministic genesis configuration (§29)
# Orbit Blockchain | Protocol v1 | Status: implemented
#
# Amounts are BIGINT STRINGS in base units (1 ORBIT = 10^8 units) — see
# orbit/core/bigint.sage for why doubles are never used for balances.
# Allocation table: plan.md §6. Sum MUST equal TOTAL_SUPPLY exactly.

import orbit.core.bigint as bi
import orbit.wallet.account as account

let DECIMALS = 8
let UNIT = "100000000"                       # base units per ORBIT

let TOTAL_SUPPLY = bi.bi_mul("100000000000", UNIT)   # 100B ORBIT in base units
let MINING_POOL_MAX = bi.bi_mul("1000000000", UNIT)  # §10: mining pool

# wallet name -> ORBIT whole-token amount (§6); converted to base units below
let ALLOCATIONS_ORBIT = {
    "system":           "81900000000",
    "lockup_rewards":   "100000000",
    "mining":           "1000000000",
    "nodefeecollector": "0",
    "community":        "3000000000",
    "team":             "5000000000",
    "airdrop":          "1000000000",
    "foundation":       "2000000000",
    "partnerships":     "1000000000",
    "reserve":          "5000000000",
}

let NETWORK_DEVNET  = "orbit-devnet"
let NETWORK_TESTNET = "orbit-testnet"
let NETWORK_MAINNET = "orbit-mainnet"

proc allocations_base_units():
    let out = {}
    for name in ALLOCATIONS_ORBIT:
        out[name] = bi.bi_mul(ALLOCATIONS_ORBIT[name], UNIT)
    return out

proc validate_allocations():
    let allocs = allocations_base_units()
    let total = "0"
    for name in allocs:
        total = bi.bi_add(total, allocs[name])
    if bi.bi_cmp(total, TOTAL_SUPPLY) != 0:
        raise "genesis allocations do not sum to TOTAL_SUPPLY"
    return true

# Deterministic devnet addresses for genesis wallets (orb-prefixed).
proc genesis_address(wallet_name):
    return account.derive_address("orbit-genesis-wallet:" + wallet_name)

proc build_genesis_state():
    validate_allocations()
    let st = {}
    let allocs = allocations_base_units()
    for name in allocs:
        st[genesis_address(name)] = {
            "balance": allocs[name],
            "nonce": 0,
            "locked_balance": "0",
            "activity_marker": 0,
            "validator_status": nil,
        }
    return st
