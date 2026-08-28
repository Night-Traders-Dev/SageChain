# t04 — transaction model, validation, ledger transitions (plan §17–§19)
import orbit.core.transaction as txmod
import orbit.core.state as statemod
import orbit.core.ledger as ledgermod
import orbit.wallet.account as account

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

let alice = account.generate_keypair("alice-devnet-seed-01")
let bob = account.generate_keypair("bob-seed-02")

let st = statemod.WorldState()
st.get(alice["address"])["balance"] = "150000000"   # 1.5 ORBIT
let pool = "100000000000000000"

proc mk_transfer(nonce, amount, fee):
    let t = txmod.Transaction(txmod.KIND_TRANSFER,
        alice["address"], bob["address"], amount, fee, nonce, 1000 + nonce)
    return txmod.sign_with(t, "alice-devnet-seed-01")

let t1 = mk_transfer(0, "100000000", "1000000")
let v1 = txmod.validate(t1, st.accounts, pool)
check("valid-transfer", v1[0])

let vr = ledgermod.Ledger(st).apply(t1, pool)
check("apply-ok", vr[0])
check("debit", st.get(alice["address"])["balance"] == "49000000")
check("credit", st.get(bob["address"])["balance"] == "100000000")
check("nonce-bumped", st.get(alice["address"])["nonce"] == 1)

# replay rejected (nonce now stale)
let v_replay = txmod.validate(t1, st.accounts, pool)
check("replay-rejected", not v_replay[0] and v_replay[1] == txmod.errors.ERR_NONCE_MISMATCH)

# insufficient balance
let big = mk_transfer(1, "49000000", "1000000")   # spend > balance (fee pushes over)
check("insufficient-rejected", not txmod.validate(big, st.accounts, pool)[0])

# tampered payload breaks signature
let t2 = mk_transfer(1, "40000000", "0")
t2.amount = "39000000"
check("tamper-detected", not txmod.validate(t2, st.accounts, pool)[0])

# reward: only from the pool sender, capped by remaining supply
let r = txmod.Transaction(txmod.KIND_REWARD, txmod.POOL_SENDER,
                          bob["address"], "5000000", "0", 0, 1002)
r.mining_context = {"users": 10, "height": 1, "score_scaled": 0, "eligible_seconds": 60}
check("reward-ok", txmod.validate(r, st.accounts, "90000000000000000")[0])
check("reward-pool-capped", not txmod.validate(r, st.accounts, "5")[0])

let fake_r = txmod.Transaction(txmod.KIND_REWARD, alice["address"],
                               bob["address"], "5000000", "0", 0, 1002)
fake_r.mining_context = {"users": 10, "height": 1, "score_scaled": 0, "eligible_seconds": 60}
check("reward-forged-sender-rejected", not txmod.validate(fake_r, st.accounts, "90000000000000000")[0])

print("t04 transaction/ledger: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t04 FAILED"
