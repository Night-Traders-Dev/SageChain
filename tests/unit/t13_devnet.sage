# t13 — 3-node devnet integration test (§52 steps 14–16, §53)
import orbit.core.chain as chainmod
import orbit.core.block as blockmod
import orbit.core.transaction as txmod
import orbit.consensus.validator as validatormod
import orbit.consensus.voting as votingmod
import orbit.consensus.poi as poimod
import orbit.consensus.finality as finalitymod
import orbit.consensus.trust as trustmod
import orbit.network.peer as peermod
import orbit.network.protocol as proto
import orbit.network.sync as syncmod
import orbit.wallet.account as account
import orbit.mining.rate as mining_rate
import orbit.mining.rewards as rewardsmod
import orbit.core.bigint as bi

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

# Three nodes with identical genesis
let net = "orbit-devnet"
let chainA = chainmod.Chain(net)
let chainB = chainmod.Chain(net)
let chainC = chainmod.Chain(net)

check("genesis-hash-match", chainA.get_block(0).hash == chainB.get_block(0).hash)
check("genesis-hash-match-C", chainA.get_block(0).hash == chainC.get_block(0).hash)

# Set up validator keys and fund them
let valA = account.generate_keypair("devnet-valA-seed")
let valB = account.generate_keypair("devnet-valB-seed")
let valC = account.generate_keypair("devnet-valC-seed")

for c in [chainA, chainB, chainC]:
    for v in [valA, valB, valC]:
        c.state.accounts[v["address"]] = {"balance": "200000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil}
    c.register_validator(valA["address"], valA["public_key"], "100000000000")
    c.register_validator(valB["address"], valB["public_key"], "100000000000")
    c.register_validator(valC["address"], valC["public_key"], "100000000000")

# Set up sync managers
let pmA = peermod.PeerManager("nodeA", net)
let pmB = peermod.PeerManager("nodeB", net)
let pmC = peermod.PeerManager("nodeC", net)
pmA.add_peer(peermod.Peer("nodeB", "nodeB", net))
pmA.add_peer(peermod.Peer("nodeC", "nodeC", net))
pmB.add_peer(peermod.Peer("nodeA", "nodeA", net))
pmB.add_peer(peermod.Peer("nodeC", "nodeC", net))
pmC.add_peer(peermod.Peer("nodeA", "nodeA", net))
pmC.add_peer(peermod.Peer("nodeB", "nodeB", net))

let syncA = syncmod.SyncManager(chainA, pmA)
let syncB = syncmod.SyncManager(chainB, pmB)
let syncC = syncmod.SyncManager(chainC, pmC)

let BLOCK_TIME = 500
let POOL_SENDER = "__mining_pool__"

proc mine_and_sync(chain_proposer, sync_proposer, proposer_addr, height, txs = nil):
    if txs == nil:
        txs = []
    let mc = {"users": 10000, "height": height, "score_scaled": 5000, "eligible_seconds": BLOCK_TIME}
    let rate = mining_rate.calculate_mining_rate(mc["users"], chain_proposer.pool_remaining, mc["height"], mc["score_scaled"])
    let reward_amt = rewardsmod.calculate_block_reward(rate, mc["eligible_seconds"], chain_proposer.pool_remaining)
    if bi.bi_cmp(reward_amt, "0") > 0:
        let rt = txmod.Transaction(txmod.KIND_REWARD, POOL_SENDER, proposer_addr, reward_amt, "0", height, height * BLOCK_TIME)
        rt.mining_context = mc
        txs = txs + [rt]
    let asm = chain_proposer.assemble_block(proposer_addr, height * BLOCK_TIME, txs, mc)
    if not asm[0]:
        raise "assemble failed at height " + str(height)
    let r = chain_proposer.apply_assembled(asm)
    if not r[0]:
        raise "apply failed: " + str(r[1])
    let blk = chain_proposer.tip()
    # Broadcast to other sync managers
    for s in [syncA, syncB, syncC]:
        if s != sync_proposer:
            let req = s.request_missing("nodeA", height, height)
            let resp = sync_proposer.handle_message({"msg": req, "from": s.peer_mgr.local_node_id})
            for b in resp[1]:
                let r2 = s._ingest_block(b)
                if not r2[0]:
                    raise "ingest failed: " + str(r2[1])
    return blk

proc vote_and_finalize(chains, height, blk_hash):
    for c in chains:
        let vote = votingmod.Vote(valA["address"], blk_hash, height, votingmod.VOTE_YES)
        votingmod.sign_vote(vote, valA["seed"])
        c.submit_vote(vote)
        let vote2 = votingmod.Vote(valB["address"], blk_hash, height, votingmod.VOTE_YES)
        votingmod.sign_vote(vote2, valB["seed"])
        c.submit_vote(vote2)
        let vote3 = votingmod.Vote(valC["address"], blk_hash, height, votingmod.VOTE_YES)
        votingmod.sign_vote(vote3, valC["seed"])
        c.submit_vote(vote3)
    for c in chains:
        let fin = c.try_finalize()
        if not fin[0]:
            print("Finalize at height " + str(height) + " not yet: " + fin[1])

# Mine 5 blocks
var h = 1
while h <= 5:
    let blk = mine_and_sync(chainA, syncA, valA["address"], h)
    vote_and_finalize([chainA, chainB, chainC], h, blk.hash)
    h = h + 1

# Verify all chains converged
check("heights-equal", chainA.height() == 5 and chainB.height() == 5 and chainC.height() == 5)
check("tip-hashes-equal", chainA.tip().hash == chainB.tip().hash and chainA.tip().hash == chainC.tip().hash)
check("state-roots-equal", chainA.state.state_root() == chainB.state.state_root() and chainA.state.state_root() == chainC.state.state_root())
check("pools-equal", chainA.pool_remaining == chainB.pool_remaining and chainA.pool_remaining == chainC.pool_remaining)

# Test transfer
let alice = account.generate_keypair("devnet-alice-seed")
let bob = account.generate_keypair("devnet-bob-seed")
for c in [chainA, chainB, chainC]:
    c.state.accounts[alice["address"]] = {"balance": "10000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil}

let t = txmod.Transaction(txmod.KIND_TRANSFER, alice["address"], bob["address"], "1000000", "1000", 0, 6 * BLOCK_TIME)
txmod.sign_with(t, "devnet-alice-seed")

let blk6 = mine_and_sync(chainA, syncA, valA["address"], 6, [t])
vote_and_finalize([chainA, chainB, chainC], 6, blk6.hash)

check("transfer-heights", chainA.height() == 6 and chainB.height() == 6 and chainC.height() == 6)
check("transfer-tips", chainA.tip().hash == chainB.tip().hash and chainA.tip().hash == chainC.tip().hash)
check("transfer-state-roots", chainA.state.state_root() == chainB.state.state_root() and chainA.state.state_root() == chainC.state.state_root())

# Verify bob received funds
check("bob-balance-A", chainA.state.accounts[bob["address"]]["balance"] == "1000000")
check("bob-balance-B", chainB.state.accounts[bob["address"]]["balance"] == "1000000")
check("bob-balance-C", chainC.state.accounts[bob["address"]]["balance"] == "1000000")

# Verify finality
check("finalized-height", chainA.finalized_height >= 6)
check("certificates-exist", dict_has(chainA.certificates, "6"))

print("t13 devnet: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t13 FAILED"