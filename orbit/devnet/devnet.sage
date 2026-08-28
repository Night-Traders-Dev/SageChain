# orbit/devnet/devnet.sage — 3-node deterministic devnet (§52 step 14+)
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.core.chain as chainmod
import orbit.core.block as blockmod
import orbit.core.transaction as txmod
import orbit.core.genesis as genesis
import orbit.consensus.validator as validatormod
import orbit.consensus.voting as votingmod
import orbit.consensus.poi as poimod
import orbit.consensus.finality as finalitymod
import orbit.consensus.trust as trustmod
import orbit.network.peer as peermod
import orbit.network.protocol as proto
import orbit.network.sync as syncmod
import orbit.wallet.account as account
import orbit.wallet.wallet as wallet
import orbit.mining.rate as mining_rate
import orbit.mining.rewards as rewardsmod
import orbit.crypto.encoding as enc

let DEVNET_NETWORK = "orbit-devnet"
let BLOCK_TIME = 500  # protocol timestamp increment per block

class DevNode:
    proc init(self, name, seed, is_validator = false):
        self.name = name
        self.seed = seed
        self.kp = account.generate_keypair(seed)
        self.address = self.kp["address"]
        self.chain = chainmod.Chain(DEVNET_NETWORK)
        self.peer_mgr = peermod.PeerManager(name, DEVNET_NETWORK)
        self.sync = syncmod.SyncManager(self.chain, self.peer_mgr)
        self.is_validator = is_validator
        self.validator_reg = None
        if is_validator:
            self.validator_reg = self.chain.validators

    proc mine_block(self, txs = nil):
        let height = self.chain.height() + 1
        let proposer = "genesis"
        if self.is_validator:
            proposer = self.address
        let ts = height * BLOCK_TIME
        if txs == nil:
            txs = []
        # Add reward tx for miner
        let mc = {
            "users": 10000,
            "height": height,
            "score_scaled": 5000,
            "eligible_seconds": BLOCK_TIME
        }
        let rate = mining_rate.calculate_mining_rate(
            mc["users"], self.chain.pool_remaining, mc["height"], mc["score_scaled"])
        let reward_amt = rewardsmod.calculate_block_reward(rate, mc["eligible_seconds"], self.chain.pool_remaining)
        if reward_amt > 0:
            let rt = txmod.Transaction(txmod.KIND_REWARD, "", proposer,
                                       str(reward_amt), "0", height, ts)
            rt.mining_context = mc
            txs = txs + [rt]
        let asm = self.chain.assemble_block(proposer, ts, txs, mc)
        if not asm[0]:
            raise "assemble failed: " + str(asm[1])
        let r = self.chain.apply_assembled(asm)
        if not r[0]:
            raise "apply failed: " + str(r[1])
        return self.chain.tip()

    proc add_peer(self, node):
        self.peer_mgr.add_peer(peermod.Peer(node.name, node.name, DEVNET_NETWORK))

    proc sync_from(self, peer_name, from_h, to_h):
        let req = self.sync.request_missing(peer_name, from_h, to_h)
        let peer = self.peer_mgr.get(peer_name)
        # This is simplified - in real impl would go over network
        return req

proc create_devnet():
    # Genesis is identical on all nodes (deterministic)
    let nodeA = DevNode("nodeA", "devnet-nodeA-seed", true)
    let nodeB = DevNode("nodeB", "devnet-nodeB-seed", true)
    let nodeC = DevNode("nodeC", "devnet-nodeC-seed", true)

    # Connect peers
    nodeA.add_peer(nodeB)
    nodeA.add_peer(nodeC)
    nodeB.add_peer(nodeA)
    nodeB.add_peer(nodeC)
    nodeC.add_peer(nodeA)
    nodeC.add_peer(nodeB)

    return [nodeA, nodeB, nodeC]

proc register_validators(nodes):
    for n in nodes:
        if n.is_validator:
            let r = n.chain.register_validator(n.address, n.kp["public_key"], "10000000000")
            print(n.name + " validator reg: " + str(r))

proc simulate_blocks(nodes, num_blocks):
    var i = 1
    while i <= num_blocks:
        let h = i
        print("=== Block " + str(h) + " ===")
        # Node A proposes
        let blk = nodes[0].mine_block()
        print(nodes[0].name + " mined: " + blk.hash[:16] + "..." + " height=" + str(blk.height))

        # Broadcast to others via sync
        var j = 1
        while j < len(nodes):
            let req = nodes[j].sync.request_missing(nodes[0].name, h, h)
            let resp = nodes[0].sync.handle_message({"msg": req, "from": nodes[j].name})
            for b in resp[1]:
                let r = nodes[j].sync._ingest_block(b)
                if not r[0]:
                    print(nodes[j].name + " ingest failed: " + str(r[1]))
                else:
                    print(nodes[j].name + " synced block " + str(b.height))
            j = j + 1

        # All validators vote
        for n in nodes:
            if n.is_validator:
                let vote = votingmod.create_vote(n.address, n.kp["seed"],
                                                 blk.hash, blk.height, true)
                n.chain.submit_vote(vote)

        # Try finalize
        for n in nodes:
            if n.is_validator:
                let fin = n.chain.try_finalize()
                if fin[0]:
                    print("Finalized at height " + str(blk.height) + " by " + n.name)

        i = i + 1
    return nodes

proc verify_convergence(nodes):
    print("=== Verifying Convergence ===")
    let ref = nodes[0].chain
    for n in nodes[1:]:
        print(n.name + " height: " + str(n.chain.height()) + " (ref: " + str(ref.height()) + ")")
        print(n.name + " tip hash: " + n.chain.tip().hash + " (ref: " + ref.tip().hash + ")")
        print(n.name + " state_root: " + n.chain.state.state_root() + " (ref: " + ref.state.state_root() + ")")
        print(n.name + " pool: " + str(n.chain.pool_remaining) + " (ref: " + str(ref.pool_remaining) + ")")
        if n.chain.height() != ref.height():
            print("FAIL: height mismatch")
            return false
        if n.chain.tip().hash != ref.tip().hash:
            print("FAIL: tip hash mismatch")
            return false
        if n.chain.state.state_root() != ref.state.state_root():
            print("FAIL: state root mismatch")
            return false
        if n.chain.pool_remaining != ref.pool_remaining:
            print("FAIL: pool mismatch")
            return false
    print("All nodes converged!")
    return true

proc test_transfer(nodes):
    print("=== Testing Transfer ===")
    let sender = nodes[0].address
    let recipient = nodes[1].address
    let nonce = nodes[0].chain.state.accounts[sender]["nonce"]
    let t = txmod.Transaction(txmod.KIND_TRANSFER, sender, recipient,
                              "1000000", "1000", nonce, nodes[0].chain.height() * BLOCK_TIME)
    txmod.sign_with(t, nodes[0].seed)
    let blk = nodes[0].mine_block([t])
    print("Transfer block: " + blk.hash[:16] + "...")
    # Sync to others
    for j in range(1, len(nodes)):
        let req = nodes[j].sync.request_missing(nodes[0].name, blk.height, blk.height)
        let resp = nodes[0].sync.handle_message({"msg": req, "from": nodes[j].name})
        for b in resp[1]:
            nodes[j].sync._ingest_block(b)
    return verify_convergence(nodes)

proc test_disconnect_reconnect(nodes):
    print("=== Testing Disconnect/Reconnect ===")
    # Simulate node C disconnecting for 2 blocks
    print("Node C disconnecting...")
    let blk1 = nodes[0].mine_block()
    for j in [0, 1]:
        let req = nodes[j].sync.request_missing(nodes[0].name, blk1.height, blk1.height)
        let resp = nodes[0].sync.handle_message({"msg": req, "from": nodes[j].name})
        for b in resp[1]:
            nodes[j].sync._ingest_block(b)

    let blk2 = nodes[0].mine_block()
    for j in [0, 1]:
        let req = nodes[j].sync.request_missing(nodes[0].name, blk2.height, blk2.height)
        let resp = nodes[0].sync.handle_message({"msg": req, "from": nodes[j].name})
        for b in resp[1]:
            nodes[j].sync._ingest_block(b)

    print("Node C reconnecting and syncing...")
    let req = nodes[2].sync.request_missing(nodes[0].name, nodes[2].chain.height() + 1, blk2.height)
    let resp = nodes[0].sync.handle_message({"msg": req, "from": nodes[2].name})
    for b in resp[1]:
        nodes[2].sync._ingest_block(b)

    return verify_convergence(nodes)

# Main devnet test
print("Starting Orbit Devnet...")
let nodes = create_devnet()
print("Created " + str(len(nodes)) + " nodes")
print("Genesis hash: " + nodes[0].chain.get_block(0).hash)

register_validators(nodes)

nodes = simulate_blocks(nodes, 5)
verify_convergence(nodes)

test_transfer(nodes)

test_disconnect_reconnect(nodes)

print("=== Devnet Test Complete ===")