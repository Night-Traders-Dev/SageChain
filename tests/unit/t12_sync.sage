# t12 — chain synchronization (§26)
import orbit.core.chain as chainmod
import orbit.network.peer as peermod
import orbit.network.protocol as proto
import orbit.network.sync as syncmod
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

# two nodes, node A mines 3 blocks, node B syncs from A
let chainA = chainmod.Chain("orbit-devnet")
let chainB = chainmod.Chain("orbit-devnet")
# fund alice on both (same genesis address, same balance injection for determinism)
let alice_seed = "sync-alice-seed"
let alice_addr = account.derive_address(alice_seed)
for c in [chainA, chainB]:
    c.state.accounts[alice_addr] = {"balance": "10000000000", "nonce": 0,
        "locked_balance": "0", "activity_marker": 0, "validator_status": nil}

proc fund_and_mine(chain, height):
    let bob = account.generate_keypair("sync-bob-" + str(height))["address"]
    let t = txmod.Transaction(txmod.KIND_TRANSFER, alice_addr, bob,
                              "1000000", "1000", height - 1, 500 + height)
    txmod.sign_with(t, alice_seed)
    let asm = chain.assemble_block(chain.tip().proposer, 500 + height, [t], nil)
    if not asm[0]:
        raise "assemble failed at height " + str(height)
    let r = chain.apply_assembled(asm)
    if not r[0]:
        raise "apply failed: " + str(r[1])
    return chain.tip()

fund_and_mine(chainA, 1)
fund_and_mine(chainA, 2)
fund_and_mine(chainA, 3)

check("A-height-3", chainA.height() == 3)

# B syncs via SyncManager: request range from A
let peerA = peermod.Peer("nodeA", "nodeA", "orbit-devnet")
let pmB = peermod.PeerManager("nodeB", "orbit-devnet")
pmB.add_peer(peerA)
let syncA = syncmod.SyncManager(chainA, peermod.PeerManager("nodeA", "orbit-devnet"))
syncA.peer_mgr.add_peer(peermod.Peer("nodeB", "nodeB", "orbit-devnet"))
let syncB = syncmod.SyncManager(chainB, pmB)

let req = syncB.request_missing("nodeA", 1, 3)
# simulate transport: B -> A
let resp = syncA.handle_message({"msg": req, "from": "nodeB"})
check("range-response-ok", resp[0])
# A -> B: deliver BLOCKS
for blk in resp[1]:
    let r2 = syncB._ingest_block(blk)
    check("block-ingest-" + str(blk.height), r2[0])

check("B-synced-height", chainB.height() == 3)
check("B-genesis-matches-A", chainB.get_block(0).hash == chainA.get_block(0).hash)
check("B-tip-matches-A", chainB.tip().hash == chainA.tip().hash)
check("B-state-root-matches-A", chainB.state.state_root() == chainA.state.state_root())
check("B-pool-matches-A", chainB.pool_remaining == chainA.pool_remaining)

print("t12 sync: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t12 FAILED"