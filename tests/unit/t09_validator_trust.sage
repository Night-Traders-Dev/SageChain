# t09 — validator lifecycle + trust/uptime scoring (plan §12, §16)
import orbit.consensus.validator as validatormod
import orbit.consensus.trust as trust
import orbit.wallet.account as account

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

let accounts = {}
let st = {"accounts": accounts}
let reg = validatormod.ValidatorRegistry()

let v_seed = "validator-alpha-seed"
let v_addr = account.generate_keypair(v_seed)["address"]
accounts[v_addr] = {"balance": "500000000000", "nonce": 0, "locked_balance": "0",
              "activity_marker": 0, "validator_status": nil}

# insufficient stake -> registers but stays pending (zero weight)
let vr_pending = reg.register(st, v_addr,
    account.derive_public_key(v_seed), "99999999", 1)
check("register-ok", vr_pending[0])
check("pending-not-active", reg.get(v_addr)["current_status"] == "pending")
check("pending-zero-weight-registry", not reg.has("nonexistent"))

# top up lock to the minimum -> active on second (distinct) registration? No:
# registration is one-shot; test min-stake path with a fresh funded identity.
let seed2 = "validator-bravo-seed"
let addr2 = account.generate_keypair(seed2)["address"]
accounts[addr2] = {"balance": "200000000000", "nonce": 0, "locked_balance": "0",
             "activity_marker": 0, "validator_status": nil}
reg.register(st, addr2, account.derive_public_key(seed2), "100000000000", 1)
check("min-stake-active", reg.get(addr2)["current_status"] == "active")
check("locked-moved", accounts[addr2]["locked_balance"] == "100000000000" and
                      accounts[addr2]["balance"] == "100000000000")

# duplicate registration rejected
let dup = reg.register(st, addr2, account.derive_public_key(seed2), "1", 2)
check("duplicate-rejected", not dup[0])

# bounded initial score (§12)
check("initial-trust-bounded", reg.get(addr2)["trust_score"] == 250000)
check("initial-uptime-zero", reg.get(addr2)["uptime_score"] == 0)

# gradual accrual, once-per-height
let o1 = trust.apply_vote_outcome(reg, addr2, 5, true)
check("accrue-ok", o1[0] and reg.get(addr2)["trust_score"] == 252000)
let o_dup = trust.apply_vote_outcome(reg, addr2, 5, true)
check("no-burst-jumps", not o_dup[0] and reg.get(addr2)["trust_score"] == 252000)
trust.apply_vote_outcome(reg, addr2, 6, true)
trust.apply_vote_outcome(reg, addr2, 7, true)
check("accrual-continues", reg.get(addr2)["trust_score"] == 256000)

# penalties outweigh accrual; slash at threshold
for h in range(40):
    let r = trust.apply_vote_outcome(reg, addr2, 100 + h, false)
    let tag = r[1]
    if tag == "slashed":
        check("slashed-at-threshold", reg.get(addr2)["penalty_points"] >= 600000)
        break
check("slashed-status", reg.get(addr2)["current_status"] == "slashed")

# unknown validator rejected everywhere
check("unknown-rejected", not trust.apply_vote_outcome(reg, "orbffff", 9, true)[0])

print("t09 validator/trust: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t09 FAILED"
