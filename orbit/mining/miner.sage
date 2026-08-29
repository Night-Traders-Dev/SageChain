# orbit/mining/miner.sage — actual miner loop with block production
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.core.chain as chainmod
import orbit.core.transaction as txmod
import orbit.core.ledger as ledgermod
import orbit.wallet.account as account
import orbit.mining.rate as mining_rate
import orbit.mining.rewards as rewardsmod
import orbit.ffi.io as ffi_io
import orbit.ffi.net as ffi_net
import orbit.ffi.bindings as ffi

# ============================================================
# MINER CONFIGURATION
# ============================================================

let MINER_CONFIG_DEFAULTS = {
    "enabled": true,
    "threads": 1,
    "max_block_time": 500,
    "proposer_address": "genesis",
    "proposer_seed": "genesis-seed",
    "mine_on_demand": false,
    "broadcast_blocks": true,
}

# ============================================================
# MINER SERVICE
# ============================================================

class MinerService:
    proc init(self, chain, config = nil):
        self.chain = chain
        self.config = config or MINER_CONFIG_DEFAULTS
        self.running = false
        self.current_proposer = self.config["proposer_address"]
        self.proposer_seed = self.config["proposer_seed"]
        self.blocks_mined = 0
        self.last_block_time = 0
        self.errors = 0

    proc start(self):
        if not self.config["enabled"]:
            return [false, "mining disabled in config"]

        if self.chain == nil:
            return [false, "chain not provided"]

        self.running = true
        return [true, nil]

    proc stop(self):
        self.running = false
        return [true, nil]

    proc get_status(self):
        return {
            "running": self.running,
            "blocks_mined": self.blocks_mined,
            "last_block_time": self.last_block_time,
            "errors": self.errors,
            "proposer": self.current_proposer,
        }

    # ============================================================
    # MAIN MINING LOOP
    # ============================================================

    proc mine_forever(self):
        while self.running:
            let result = self.mine_once()
            if not result[0]:
                self.errors = self.errors + 1
                ffi.ffi_log("error", "mining failed: " + result[1])
                ffi.ffi_sleep_ms(1000)  # back off on error
            else:
                self.blocks_mined = self.blocks_mined + 1
                self.last_block_time = ffi.ffi_time_now()
                ffi.ffi_log("info", "mined block " + str(self.chain.height()) + ": " + result[1].hash[:16] + "...")

            # Sleep between blocks
            if self.config["max_block_time"] > 0:
                ffi.ffi_sleep_ms(self.config["max_block_time"])

        return [true, nil]

    # Mine a single block
    proc mine_once(self):
        let height = self.chain.height() + 1
        let timestamp = height * self.config["max_block_time"]

        # Calculate mining rate
        let mc = {
            "users": 10000,  # would come from active user count
            "height": height,
            "score_scaled": 500000,  # 0.5 on 1e6 scale
            "eligible_seconds": self.config["max_block_time"],
        }

        let rate = mining_rate.calculate_mining_rate(
            mc["users"], self.chain.pool_remaining, mc["height"], mc["score_scaled"])
        let reward_amt = rewardsmod.calculate_block_reward(
            rate, mc["eligible_seconds"], self.chain.pool_remaining)

        # Build transactions
        let txs = []

        # Add reward transaction if reward > 0
        if reward_amt > 0:
            let rt = txmod.Transaction(txmod.KIND_REWARD, "", self.current_proposer,
                                       str(reward_amt), "0", height, timestamp)
            rt.mining_context = mc
            rt.gas_limit = 1000000
            rt.value = "0"
            txs = txs + [rt]

        # Add pending transactions from mempool (placeholder)
        let pending = self.get_pending_transactions()
        txs = txs + pending

        # Assemble block
        let asm = self.chain.assemble_block(self.current_proposer, timestamp, txs, mc)
        if not asm[0]:
            return [false, "assemble failed: " + str(asm[1])]

        # Apply block
        let r = self.chain.apply_assembled(asm)
        if not r[0]:
            return [false, "apply failed: " + str(r[1])]

        let block = self.chain.tip()

        # Broadcast block if enabled
        if self.config["broadcast_blocks"]:
            self.broadcast_block(block)

        return [true, block]

    # Get pending transactions from mempool
    proc get_pending_transactions(self):
        # In production, this would pull from a mempool
        return []

    # Broadcast block to network
    proc broadcast_block(self, block):
        # In production, would use P2P transport
        ffi.ffi_log("info", "broadcasting block " + block.hash[:16] + "...")
        return true

    # Set proposer (for validator rotation)
    proc set_proposer(self, address, seed):
        self.current_proposer = address
        self.proposer_seed = seed

# ============================================================
# SOLO MINER (single-threaded, for devnet)
# ============================================================

proc run_solo_miner(chain, config):
    let miner = MinerService(chain, config)
    let start_result = miner.start()
    if not start_result[0]:
        return start_result

    ffi.ffi_log("info", "miner started")
    let result = miner.mine_forever()
    miner.stop()
    return result

# ============================================================
# MULTI-THREADED MINER (placeholder)
# ============================================================

class ThreadPool:
    proc init(self, num_threads):
        self.num_threads = num_threads
        self.workers = []

    proc start(self, worker_fn):
        # In production, would spawn actual threads
        for i in range(self.num_threads):
            push(self.workers, {"id": i, "running": true})

    proc stop(self):
        for w in self.workers:
            w["running"] = false

    proc submit(self, task):
        # Submit to worker queue
        return true

class ParallelMiner:
    proc init(self, chain, num_threads = 1):
        self.chain = chain
        self.pool = ThreadPool(num_threads)

    proc start(self):
        self.pool.start(proc():
            while true:
                # Each worker would mine on different nonces
                pass
            )
        return true

    proc stop(self):
        self.pool.stop()

# ============================================================
# MINER FACTORY
# ============================================================

proc create_miner(chain, config = nil):
    return MinerService(chain, config)