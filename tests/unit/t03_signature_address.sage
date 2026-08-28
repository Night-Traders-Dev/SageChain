# t03 — orb addresses + Lamport sign/verify (plan §23, §24)
import orbit.wallet.account as account
import orbit.crypto.signatures as sig

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

let kp = account.generate_keypair("alice-devnet-seed-01")
check("prefix-orb", slice(kp["address"], 0, 3) == "orb")
check("address-len", len(kp["address"]) == 43)
check("deterministic", account.derive_address("alice-devnet-seed-01") == kp["address"])
check("distinct-seeds", account.derive_address("bob-seed-02") != kp["address"])
check("validator-ok", account.is_valid_address(kp["address"]))
check("validator-bad-prefix", not account.is_valid_address("xrb" + slice(kp["address"], 3, 43)))
check("validator-short", not account.is_valid_address(slice(kp["address"], 0, 42)))
check("validator-nonhex", not account.is_valid_address("orbZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"))

let msg = "orbit test payload 001"
let s = sig.sign(kp["seed"], msg)
check("verify-ok", sig.verify(kp["public_key"], msg, s))
check("verify-tampered-msg", not sig.verify(kp["public_key"], msg + "!", s))
check("verify-wrong-key", not sig.verify(account.derive_public_key("bob-seed-02"), msg, s))

var truncated = []
for i in range(31):
    push(truncated, s[i])
check("verify-truncated-sig", not sig.verify(kp["public_key"], msg, truncated))

print("t03 signature/address: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t03 FAILED"
