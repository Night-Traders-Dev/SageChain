# t14 — token lockups (§18)
import orbit.core.chain as chainmod
import orbit.core.transaction as txmod
import orbit.core.ledger as ledgermod
import orbit.core.state as statemod
import orbit.wallet.account as account
import orbit.core.bigint as bi

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

let net = "orbit-devnet"
let chain = chainmod.Chain(net)

# Create test account
let alice = account.generate_keypair("lockup-alice-seed")
chain.state.accounts[alice["address"]] = {"balance": "10000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil, "lockups": {}}

check("initial-balance", chain.state.accounts[alice["address"]]["balance"] == "10000000000")
check("initial-locked", chain.state.accounts[alice["address"]]["locked_balance"] == "0")

# Test lock transaction
let lock_ts = 1000
let lock_duration = 100  # 100 blocks
let claim_height = lock_ts + lock_duration
let lock_tx = txmod.Transaction(txmod.KIND_LOCK, alice["address"], alice["address"], "5000000000", "1000", 0, lock_ts)
lock_tx.lock_duration = lock_duration
lock_tx.claim_height = claim_height
lock_tx.lockup_id = "lockup-1"
txmod.sign_with(lock_tx, "lockup-alice-seed")

let vr = txmod.validate(lock_tx, chain.state.accounts, chain.pool_remaining)
check("lock-validate", vr[0])

let ldg = ledgermod.Ledger(chain.state)
let ar = ldg.apply(lock_tx, chain.pool_remaining)
check("lock-apply", ar[0])

check("lock-balance", chain.state.accounts[alice["address"]]["balance"] == "4999999000")
check("lock-locked", chain.state.accounts[alice["address"]]["locked_balance"] == "5000000000")
check("lock-lockup-exists", chain.state.accounts[alice["address"]]["lockups"]["lockup-1"] != nil)
check("lock-lockup-amount", chain.state.accounts[alice["address"]]["lockups"]["lockup-1"]["amount"] == "5000000000")
check("lock-lockup-status", chain.state.accounts[alice["address"]]["lockups"]["lockup-1"]["status"] == "LOCKED")
check("lock-lockup-claim-height", chain.state.accounts[alice["address"]]["lockups"]["lockup-1"]["claim_height"] == str(claim_height))

# Test unlock before duration - should fail
let unlock_tx_early = txmod.Transaction(txmod.KIND_UNLOCK, alice["address"], "", "0", "1000", 1, lock_ts + 50)
unlock_tx_early.lockup_id = "lockup-1"
txmod.sign_with(unlock_tx_early, "lockup-alice-seed")

let vr2 = txmod.validate(unlock_tx_early, chain.state.accounts, chain.pool_remaining)
check("unlock-early-validate", vr2[0])
let ar2 = ldg.apply(unlock_tx_early, chain.pool_remaining)
check("unlock-early-fail", not ar2[0])
check("unlock-early-err", ar2[1] == "lock_duration_not_met")

# Test unlock after duration
let unlock_tx = txmod.Transaction(txmod.KIND_UNLOCK, alice["address"], "", "0", "1000", 1, lock_ts + 150)
unlock_tx.lockup_id = "lockup-1"
txmod.sign_with(unlock_tx, "lockup-alice-seed")

let vr3 = txmod.validate(unlock_tx, chain.state.accounts, chain.pool_remaining)
check("unlock-validate", vr3[0])
let ar3 = ldg.apply(unlock_tx, chain.pool_remaining)
check("unlock-apply", ar3[0])

check("unlock-balance", chain.state.accounts[alice["address"]]["balance"] == "9999999000")
check("unlock-locked", chain.state.accounts[alice["address"]]["locked_balance"] == "0")
check("unlock-status", chain.state.accounts[alice["address"]]["lockups"]["lockup-1"]["status"] == "UNLOCKED")

# Test lock again for claim test
let lock_tx2 = txmod.Transaction(txmod.KIND_LOCK, alice["address"], alice["address"], "3000000000", "1000", 2, lock_ts + 200)
lock_tx2.lock_duration = lock_duration
lock_tx2.claim_height = lock_ts + 200 + lock_duration
lock_tx2.lockup_id = "lockup-2"
txmod.sign_with(lock_tx2, "lockup-alice-seed")

let vr4 = txmod.validate(lock_tx2, chain.state.accounts, chain.pool_remaining)
check("lock2-validate", vr4[0])
let ar4 = ldg.apply(lock_tx2, chain.pool_remaining)
check("lock2-apply", ar4[0])

# Test claim before claim_height - should fail
let claim_tx_early = txmod.Transaction(txmod.KIND_CLAIM, alice["address"], "", "0", "1000", 3, lock_ts + 250)
claim_tx_early.lockup_id = "lockup-2"
txmod.sign_with(claim_tx_early, "lockup-alice-seed")

let vr5 = txmod.validate(claim_tx_early, chain.state.accounts, chain.pool_remaining)
check("claim-early-validate", vr5[0])
let ar5 = ldg.apply(claim_tx_early, chain.pool_remaining)
check("claim-early-fail", not ar5[0])
check("claim-early-err", ar5[1] == "claim_not_ready")

# Test claim after claim_height
let claim_ts = lock_ts + 200 + lock_duration + 10
let claim_tx = txmod.Transaction(txmod.KIND_CLAIM, alice["address"], "", "0", "1000", 3, claim_ts)
claim_tx.lockup_id = "lockup-2"
txmod.sign_with(claim_tx, "lockup-alice-seed")

let vr6 = txmod.validate(claim_tx, chain.state.accounts, chain.pool_remaining)
check("claim-validate", vr6[0])
let ar6 = ldg.apply(claim_tx, chain.pool_remaining)
check("claim-apply", ar6[0])

check("claim-reward-positive", bi.bi_cmp(chain.state.accounts[alice["address"]]["balance"], "6999997000") > 0)
check("claim-status", chain.state.accounts[alice["address"]]["lockups"]["lockup-2"]["status"] == "CLAIMED")

# Test claim again - should fail
let claim_tx2 = txmod.Transaction(txmod.KIND_CLAIM, alice["address"], "", "0", "1000", 4, claim_ts + 100)
claim_tx2.lockup_id = "lockup-2"
txmod.sign_with(claim_tx2, "lockup-alice-seed")

let vr7 = txmod.validate(claim_tx2, chain.state.accounts, chain.pool_remaining)
check("claim2-validate", vr7[0])
let ar7 = ldg.apply(claim_tx2, chain.pool_remaining)
check("claim2-fail", not ar7[0])

# Test state root determinism with lockups
let st1 = chain.state.clone()
let root1 = st1.state_root()

let chain2 = chainmod.Chain(net)
chain2.state.accounts[alice["address"]] = {"balance": "10000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil, "lockups": {}}

# Apply same sequence
ldg = ledgermod.Ledger(chain2.state)
ldg.apply(lock_tx, chain2.pool_remaining)
ldg.apply(unlock_tx, chain2.pool_remaining)
ldg.apply(lock_tx2, chain2.pool_remaining)
ldg.apply(claim_tx, chain2.pool_remaining)

let root2 = chain2.state.state_root()
check("state-root-deterministic", root1 == root2)

print("t14 lockup: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t14 FAILED"