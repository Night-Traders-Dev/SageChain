# t06 — genesis invariants + single-node chain lifecycle (plan §29, §38, §53)
import orbit.core.chain as chainmod
import orbit.core.genesis as genesis
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

check("allocations-sum", genesis.validate_allocations())
let chain = chainmod.Chain(genesis.NETWORK_DEVNET)
check("genesis-height", chain.height() == 0)
check("genesis-hash-set", len(chain.tip().hash) == 64)
check("pool-at-max", chain.pool_remaining == genesis.MINING_POOL_MAX)

let chain_b = chainmod.Chain(genesis.NETWORK_DEVNET)
check("genesis-deterministic", chain_b.tip().hash == chain.tip().hash)
check("devnet-vs-mainnet-differ",
      chainmod.Chain(genesis.NETWORK_MAINNET).tip().hash != chain.tip().hash)

let sys_addr = genesis.genesis_address("system")
check("genesis-system-funded",
      chain.state.accounts[sys_addr]["balance"] == "8190000000000000000")

let alice_seed = "alice-devnet-seed-01"
chain.state.accounts[account.derive_address(alice_seed)] = {
    "balance": "150000000", "nonce": 0, "locked_balance": "0",
    "activity_marker": 0, "validator_status": nil,
}
let bob_addr = account.generate_keypair("bob-seed-02")["address"]

proc mk_tx(nonce, amount, fee, ts):
    let t = txmod.Transaction(txmod.KIND_TRANSFER,
        account.derive_address(alice_seed), bob_addr, amount, fee, nonce, ts)
    return txmod.sign_with(t, alice_seed)

let tx_a = mk_tx(0, "100000000", "1000000", 1001)
let asm1 = chain.assemble_block(chain.tip().proposer, 1001, [tx_a], nil)
check("assemble-ok", asm1[0])
let blk1 = asm1[1]["block"]
check("tx-root-set", blk1.tx_root != nil)
check("hash-len", len(blk1.hash) == 64)
let ap = chain.apply_assembled(asm1)
check("append-ok", ap[0])
check("height-advanced", chain.height() == 1)
check("alice-debited",
      chain.state.get(account.derive_address(alice_seed))["balance"] == "49000000")
check("bob-credited", chain.state.get(bob_addr)["balance"] == "100000000")

import orbit.core.block as blockmod
let evil = blockmod.Block(99, "deadbeef" * 8)
evil.transactions = []
evil.proposer = "evil"
check("broken-link-rejected", not chain.append_block(evil)[0])

let evil2 = blockmod.Block(chain.height() + 1, chain.tip().hash)
evil2.timestamp = chain.tip().timestamp + 10
let good_tx = mk_tx(1, "1000000", "0", 1010)
push(evil2.transactions, good_tx)
# finalize honestly, then tamper AFTER hashing -> commitment must catch it
blockmod.finalize(evil2, chain.state)
evil2.transactions[0].memo = "tampered"
let vr_tamper = chain.append_block(evil2)
check("tampered-tx-root-rejected", not vr_tamper[0])
if not vr_tamper[0]:
    check("tamper-error-code", vr_tamper[1] == "malformed_block")

print("t06 genesis/chain: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t06 FAILED"
