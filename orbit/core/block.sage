# orbit/core/block.sage — block model, hashing, validation (plan §20–§21)
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.core.merkle as merkle
import orbit.core.transaction as txmod
import orbit.core.ledger as ledgermod
import orbit.mining.rate as mining_rate
from crypto.hash import sha256_hex

class Block:
    proc init(self, height, previous_hash, network_id = "orbit-devnet"):
        self.version = 1
        self.network_id = network_id
        self.height = height
        self.previous_hash = previous_hash
        self.state_root = nil
        self.tx_root = nil
        self.validator_root = nil
        self.proposer = nil
        self.timestamp = 0            # protocol timestamp (monotonic)
        self.protocol_id = 1
        self.proof = nil              # {eligible_seconds, users, score_scaled}
        self.hash = nil
        self.transactions = []

proc header_dict(b):
    # EXACT field set for block_hash (§21) — order fixed by canonical encoder
    return {
        "version": b.version,
        "network_id": b.network_id,
        "height": b.height,
        "previous_hash": b.previous_hash,
        "state_root": b.state_root,
        "tx_root": b.tx_root,
        "validator_root": b.validator_root,
        "proposer": b.proposer,
        "timestamp": b.timestamp,
        "protocol_id": b.protocol_id,
        "proof": b.proof,
    }

proc compute_tx_root(b):
    import orbit.crypto.encoding as encoding
    let leaves = []
    for t in b.transactions:
        push(leaves, sha256_hex(encoding.encode_canonical(txmod.canonical_fields(t))))
    return merkle.root(leaves)

proc compute_hash(b):
    import orbit.crypto.encoding as encoding
    return sha256_hex(encoding.encode_canonical(header_dict(b)))

proc finalize(b, world_state, validator_registry = nil):
    b.tx_root = compute_tx_root(b)
    b.state_root = world_state.state_root()
    if validator_registry != nil:
        b.validator_root = validator_registry.root()
    b.hash = compute_hash(b)
    return b

# Full deterministic validation against parent block/state/pool.
# Returns [ok, error].
proc validate_block(parent, b, parent_state, pool_remaining):
    import orbit.core.state as statemod
    import orbit.core.errors as errors

    if b.protocol_id != 1:
        return [false, errors.ERR_BAD_BLOCK]
    if b.height != parent.height + 1:
        return [false, errors.ERR_LINK_BROKEN]
    if b.previous_hash != parent.hash:
        return [false, errors.ERR_LINK_BROKEN]
    if b.timestamp <= parent.timestamp:
        return [false, errors.ERR_BAD_BLOCK]

    if b.tx_root != compute_tx_root(b):
        return [false, errors.ERR_BAD_BLOCK]

    # replay every transaction against a copy of parent state
    let st = parent_state.clone()
    var pool = pool_remaining
    let ldg = ledgermod.Ledger(st)

    var prev_ts = parent.timestamp
    for t in b.transactions:
        # protocol timestamps must be monotonic inside the block too
        if t.timestamp <= prev_ts and t.kind != txmod.KIND_REWARD:
            return [false, errors.ERR_BAD_BLOCK]
        prev_ts = t.timestamp

        if t.kind == txmod.KIND_REWARD:
            # recompute the rate from committed consensus inputs (§17 reward)
            if t.mining_context == nil:
                return [false, errors.ERR_INVALID_TX]
            let mc = t.mining_context
            let expect = mining_rate.calculate_mining_rate(
                mc["users"], pool, mc["height"], mc["score_scaled"])
            let want = rewards_amount(expect, mc["eligible_seconds"], pool)
            if t.amount != want:
                return [false, errors.ERR_INVALID_TX]

        let vr = txmod.validate(t, st.accounts, pool)
        if not vr[0]:
            return [vr]
        let ar = ldg.apply(t, pool)
        if not ar[0]:
            return [false, errors.ERR_BAD_BLOCK]
        pool = ar[2]

    # Proposer must be a real, funded account — except the system proposer
    # "genesis", which assembles pre-consensus blocks (deeper PoI proposer
    # rotation lands in Phase 5 with multi-node networking).
    if b.proposer == nil:
        return [false, errors.ERR_BAD_BLOCK]
    if b.proposer != "genesis" and not dict_has(st.accounts, b.proposer):
        return [false, errors.ERR_BAD_BLOCK]

    if b.state_root != st.state_root():
        return [false, errors.ERR_BAD_BLOCK]

    return [true, pool]

proc rewards_amount(rate_value, eligible_seconds, pool):
    import orbit.mining.rewards as rw
    return rw.calculate_block_reward(rate_value, eligible_seconds, pool)
