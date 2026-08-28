# t08 — cross-node determinism, condensed from plan §43:
# identical genesis + identical transactions + identical inputs
# MUST produce byte-identical block hashes and state roots.

import orbit.core.chain as chainmod
import orbit.core.transaction as txmod
import orbit.wallet.account as account

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

proc build_node():
    let c = chainmod.Chain("orbit-devnet")
    let seed = "determinism-alice-42"
    c.state.accounts[account.derive_address(seed)] = {
        "balance": "999000000", "nonce": 0, "locked_balance": "0",
        "activity_marker": 0, "validator_status": nil,
    }
    let bob = account.generate_keypair("determinism-bob")["address"]
    proc mk(nonce, amount, fee, ts):
        let t = txmod.Transaction(txmod.KIND_TRANSFER,
            account.derive_address(seed), bob, amount, fee, nonce, ts)
        return txmod.sign_with(t, seed)
    let a1 = c.assemble_block("genesis", 500, [mk(0, "1000000", "1000", 500)], nil)
    let r1 = c.apply_assembled(a1)
    let a2 = c.assemble_block("genesis", 600, [mk(1, "2000000", "1000", 600)], nil)
    let r2 = c.apply_assembled(a2)
    return {"hash1": c.get_block(1).hash, "hash2": c.get_block(2).hash,
            "root": c.state.state_root(), "pool": c.pool_remaining}

let n1 = build_node()
let n2 = build_node()

check("block1-hash-identical", n1["hash1"] == n2["hash1"])
check("block2-hash-identical", n1["hash2"] == n2["hash2"])
check("state-root-identical", n1["root"] == n2["root"])
check("pool-identical", n1["pool"] == n2["pool"])

print("t08 determinism: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t08 FAILED"
