# orbit/core/chain.sage — single-node chain orchestration (plan §53)
# Orbit Blockchain | Protocol v1 | Status: implemented
#
# Owns: finalized blocks, world state, remaining mining pool.
# append_block() is the ONLY way state changes; every mutation follows
# deterministic validation. Result convention: [ok, err_or_new_pool].

import orbit.core.bigint as bi
import orbit.core.block as blockmod
import orbit.core.errors as errors
import orbit.core.genesis as genesis
import orbit.core.state as statemod
import orbit.consensus.validator as validatormod
import orbit.consensus.trust as trustmod
import orbit.consensus.voting as votingmod
import orbit.consensus.poi as poimod
import orbit.consensus.finality as finalitymod

class Chain:
    proc init(self, network_id):
        let allocs_ok = genesis.validate_allocations()
        self.network_id = network_id
        self.state = statemod.WorldState()
        self.blocks = []
        self.pool_remaining = genesis.MINING_POOL_MAX
        self.validators = validatormod.ValidatorRegistry()
        self.vote_pool = []            # votes for the CURRENT tip
        self.finalized_height = 0      # nothing finalized at genesis
        self.certificates = {"_": nil}  # Sage requires non-empty dict for assignment
        dict_delete(self.certificates, "_")
        # Contracts (Phase 10) - use state.contracts for consistency with ledger
        # self.contracts = {}

        # ── build genesis (height 0) ──
        let accounts = genesis.build_genesis_state()
        for addr in accounts:
            self.state.accounts[addr] = accounts[addr]

        # Network identity is consensus-critical: different networks MUST
        # produce different genesis hashes (plan §29).
        import orbit.crypto.encoding as encoding
        from crypto.hash import sha256_hex
        let g = blockmod.Block(0, sha256_hex("orbit-genesis:" + network_id), network_id)
        g.timestamp = 0
        g.proposer = "genesis"
        blockmod.finalize(g, self.state, self.validators)

        if g.hash == nil:
            raise "genesis hash failed"
        push(self.blocks, g)

    proc tip(self):
        return self.blocks[len(self.blocks) - 1]

    proc height(self):
        return self.tip().height

    proc get_block(self, height):
        if height < 0 or height >= len(self.blocks):
            return nil
        return self.blocks[height]

    # Contract methods (Phase 10)
    proc get_contract(self, addr):
        if dict_has(self.state.contracts, addr):
            return self.state.contracts[addr]
        return nil

    proc set_contract(self, addr, contract):
        self.state.contracts[addr] = contract
        return true

    proc contract_state_root(self):
        import orbit.core.merkle as merkle
        import orbit.crypto.encoding as encoding
        import orbit.crypto.encoding as enc
        from crypto.hash import sha256_hex
        let addrs = []
        for addr in self.contracts:
            push(addrs, addr)
        let sorted = encoding.sort_strings(addrs)
        let leaves = []
        for addr in sorted:
            let c = self.contracts[addr]
            push(leaves, sha256_hex(enc.encode_canonical([addr, c.balance, c.nonce])))
        return merkle.root(leaves)

    # Assemble a block from validated-ready transactions and commit inputs.
    proc assemble_block(self, proposer, timestamp, transactions, proof):
        let b = blockmod.Block(self.height() + 1, self.tip().hash, self.network_id)
        b.proposer = proposer
        b.timestamp = timestamp
        b.proof = proof
        b.transactions = transactions

        let st = self.state.clone()
        var pool = self.pool_remaining
        import orbit.core.ledger as ledgermod
        import orbit.core.transaction as txmod
        let ldg = ledgermod.Ledger(st)
        var prev_ts = self.tip().timestamp
        for t in transactions:
            if t.kind == txmod.KIND_REWARD and t.mining_context != nil:
                let mc = t.mining_context
                let expected_rate = mining_rate_for(mc, pool)
                t.amount = expected_reward(expected_rate, mc, pool)
            let vr = txmod.validate(t, st.accounts, pool)
            if not vr[0]:
                return [false, vr[1]]
            let ar = ldg.apply(t, pool)
            pool = ar[2]
            prev_ts = t.timestamp
        blockmod.finalize(b, st, self.validators)
        return [true, {"block": b, "state": st, "pool": pool}]


    # ── PoI consensus (plan §15–§16) ─────────────────────────────────
    # Register a validator: locks self-stake, activates at/above minimum.
    proc register_validator(self, addr, public_key, stake):
        let vr = self.validators.register(self.state, addr, public_key, stake,
                                          self.height())
        return vr

    # Submit a signed vote for the CURRENT tip. Valid votes enter the pool;
    # invalid ones are reported back for trust penalties.
    proc submit_vote(self, vote):
        let vr = votingmod.validate(vote, self.validators)
        if not vr[0]:
            return [false, vr[1]]
        if vote.block_hash != self.tip().hash or vote.height != self.height():
            return [false, "stale_vote"]
        for existing in self.vote_pool:
            if existing.validator_addr == vote.validator_addr:
                return [false, "duplicate_vote"]
        push(self.vote_pool, vote)
        trustmod.apply_uptime_observation(self.validators, vote.validator_addr, true)
        return [true, nil]

    # Tally the pool against the tip; produce a certificate when the 2/3
    # threshold is met; apply per-vote trust outcomes deterministically.
    proc try_finalize(self):
        let res = poimod.evaluate_candidate(self.vote_pool, self.validators,
                                            self.tip().hash, self.height())
        # penalties for invalid votes (bounded once-per-height inside trust)
        for entry in res["invalid"]:
            trustmod.apply_vote_outcome(self.validators, entry[0],
                                        self.height(), false)
        for v in self.vote_pool:
            trustmod.apply_vote_outcome(self.validators, v.validator_addr,
                                        self.height(), true)
        if res["certificate"] != nil:
            let hkey = str(self.height())
            self.certificates[hkey] = res["certificate"]
            self.finalized_height = self.height()
            self.vote_pool = []          # consumed
            return [true, res["certificate"]]
        return [false, "threshold_not_met"]

    # §27: no reorganization past finalized height.
    proc check_reorg_rule(self, parent_height):
        if parent_height < self.finalized_height:
            return [false, "reorg_past_finality"]
        return [true, nil]

    proc append_block(self, b):
        let rr = self.check_reorg_rule(b.height - 1)
        if not rr[0]:
            return rr
        let vr = blockmod.validate_block(self.tip(), b, self.state, self.pool_remaining)
        if not vr[0]:
            return [false, vr[1]]
        # validator_root must match registry state when provided
        if b.validator_root != nil and b.validator_root != self.validators.root():
            return [false, errors.ERR_BAD_BLOCK]
        # Replay transactions to update state and pool (same logic as validate_block)
        let st = self.state.clone()
        var pool = self.pool_remaining
        import orbit.core.ledger as ledgermod
        let ldg = ledgermod.Ledger(st)
        for t in b.transactions:
            let ar = ldg.apply(t, pool)
            pool = ar[2]
        self.state = st
        self.pool_remaining = pool
        push(self.blocks, b)
        return [true, nil]

    proc apply_assembled(self, assembled_result):
        # append a block produced by assemble_block; input is its
        # [ok, {block,state,pool}] result pair.
        if not assembled_result[0]:
            return [false, "assemble_failed"]
        let payload = assembled_result[1]
        let b = payload["block"]
        let vr = blockmod.validate_block(self.tip(), b, self.state, self.pool_remaining)
        if not vr[0]:
            return [false, vr[1]]
        self.state = payload["state"]
        self.pool_remaining = payload["pool"]
        push(self.blocks, b)
        return [true, nil]

proc mining_rate_for(mc, pool):
    import orbit.mining.rate as rate
    return rate.calculate_mining_rate(mc["users"], pool, mc["height"], mc["score_scaled"])

proc expected_reward(rate_value, mc, pool):
    import orbit.mining.rewards as rewards
    return rewards.calculate_block_reward(rate_value, mc["eligible_seconds"], pool)
