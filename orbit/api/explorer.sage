# orbit/api/explorer.sage — explorer backend queries (§32)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.core.chain as chainmod
import orbit.core.block as blockmod
import orbit.core.transaction as txmod
import orbit.consensus.validator as validatormod
import orbit.mining.rate as mining_rate
import orbit.core.bigint as bi
import orbit.crypto.encoding as enc

proc _max(a, b):
    if a > b:
        return a
    return b

# Block queries
proc get_block_by_height(chain, height):
    let blk = chain.get_block(height)
    if blk == nil:
        return [false, "block not found"]
    return [true, _block_summary(blk)]

proc get_block_by_hash(chain, hash):
    for blk in chain.blocks:
        if blk.hash == hash:
            return [true, _block_summary(blk)]
    return [false, "block not found"]

proc get_latest_block(chain):
    return [true, _block_summary(chain.tip())]

proc list_blocks(chain, page = 0, limit = 20):
    let start = chain.height() - page * limit
    let end = _max(0, start - limit + 1)
    let blocks = []
    var h = start
    while h >= end and h >= 0:
        let blk = chain.get_block(h)
        if blk != nil:
            push(blocks, _block_summary(blk))
        h = h - 1
    return [true, {"blocks": blocks, "page": page, "limit": limit, "total": chain.height() + 1}]

proc _block_summary(blk):
    let txs = []
    for t in blk.transactions:
        push(txs, {
            "tx_id": t.tx_id,
            "kind": t.kind,
            "sender": t.sender,
            "recipient": t.recipient,
            "amount": t.amount,
            "fee": t.fee,
        })
    return {
        "hash": blk.hash,
        "height": blk.height,
        "previous_hash": blk.previous_hash,
        "state_root": blk.state_root,
        "tx_root": blk.tx_root,
        "validator_root": blk.validator_root,
        "proposer": blk.proposer,
        "timestamp": blk.timestamp,
        "protocol_id": blk.protocol_id,
        "proof": blk.proof,
        "finalized": blk.height <= 0,  # will be checked against chain.finalized_height
        "transactions": txs,
    }

# Transaction queries
proc get_tx_by_id(chain, txid):
    for blk in chain.blocks:
        for t in blk.transactions:
            if t.tx_id == txid:
                return [true, _tx_detail(t, blk.height)]
    return [false, "tx not found"]

proc list_txs(chain, page = 0, limit = 50):
    let txs = []
    let count = 0
    var h = chain.height()
    while h >= 0 and count < (page + 1) * limit:
        let blk = chain.get_block(h)
        if blk != nil:
            for t in blk.transactions:
                if count >= page * limit and count < (page + 1) * limit:
                    push(txs, _tx_detail(t, blk.height))
                count = count + 1
        h = h - 1
    return [true, {"transactions": txs, "page": page, "limit": limit, "total": count}]

proc _tx_detail(t, block_height):
    return {
        "tx_id": t.tx_id,
        "block_height": block_height,
        "kind": t.kind,
        "sender": t.sender,
        "recipient": t.recipient,
        "amount": t.amount,
        "fee": t.fee,
        "nonce": t.nonce,
        "timestamp": t.timestamp,
        "memo": t.memo,
    }

# Address queries
proc get_address(chain, address):
    let acc = chain.state.accounts[address]
    if acc == nil:
        return [false, "address not found"]
    return [true, {
        "address": address,
        "balance": acc["balance"],
        "nonce": acc["nonce"],
        "locked_balance": acc["locked_balance"],
        "activity_marker": acc["activity_marker"],
        "validator_status": acc["validator_status"],
    }]

proc get_address_txs(chain, address, limit = 20):
    let recent_txs = []
    var h = chain.height()
    var found = 0
    while h >= 0 and found < limit:
        let blk = chain.get_block(h)
        if blk != nil:
            for t in blk.transactions:
                if t.sender == address or t.recipient == address:
                    let dir = "in"
                    if t.sender == address:
                        dir = "out"
                    push(recent_txs, {
                        "tx_id": t.tx_id,
                        "block_height": blk.height,
                        "kind": t.kind,
                        "sender": t.sender,
                        "recipient": t.recipient,
                        "amount": t.amount,
                        "fee": t.fee,
                        "direction": dir,
                    })
                    found = found + 1
        h = h - 1
    return [true, {"address": address, "transactions": recent_txs}]

# Validator queries
proc list_validators(chain):
    let out = []
    for addr in chain.validators.validators:
        let v = chain.validators.validators[addr]
        push(out, {
            "address": v.address,
            "public_key": v.public_key,
            "activation_height": v.activation_height,
            "last_seen_height": v.last_seen_height,
            "uptime_score": v.uptime_score,
            "trust_score": v.trust_score,
            "valid_vote_count": v.valid_vote_count,
            "invalid_vote_count": v.invalid_vote_count,
            "proposed_blocks": v.proposed_blocks,
            "accepted_blocks": v.accepted_blocks,
            "penalty_points": v.penalty_points,
            "status": v.current_status,
        })
    return [true, {"validators": out}]

proc get_validator(chain, address):
    let v = chain.validators.get(address)
    if v == nil:
        return [false, "validator not found"]
    return [true, {
        "address": v.address,
        "public_key": v.public_key,
        "activation_height": v.activation_height,
        "last_seen_height": v.last_seen_height,
        "uptime_score": v.uptime_score,
        "trust_score": v.trust_score,
        "valid_vote_count": v.valid_vote_count,
        "invalid_vote_count": v.invalid_vote_count,
        "proposed_blocks": v.proposed_blocks,
        "accepted_blocks": v.accepted_blocks,
        "penalty_points": v.penalty_points,
        "status": v.current_status,
    }]

# Mining queries
proc get_mining_stats(chain):
    let tip = chain.tip()
    let rate = mining_rate.calculate_mining_rate(
        10000, chain.pool_remaining, tip.height, 500000)
    let blocks = []
    var h = tip.height
    let min_h = tip.height - 100
    if min_h < 0:
        min_h = 0
    while h >= min_h:
        let blk = chain.get_block(h)
        if blk != nil and len(blk.transactions) > 0:
            for t in blk.transactions:
                if t.kind == "reward":
                    push(blocks, {
                        "height": blk.height,
                        "reward": t.amount,
                        "mining_context": t.mining_context,
                    })
                    break
        h = h - 1
    return [true, {
        "current_rate": rate,
        "pool_remaining": chain.pool_remaining,
        "pool_exhausted_pct": int((1000000 * (100000000000000000 - chain.pool_remaining)) / 100000000000000000),
        "recent_rewards": blocks,
    }]

# Network queries
proc get_network_health(chain):
    return [true, {
        "height": chain.height(),
        "finalized_height": chain.finalized_height,
        "finality_lag": chain.height() - chain.finalized_height,
        "validator_count": chain.validators.active_count(),
        "peer_count": 0,
        "pool_remaining": chain.pool_remaining,
    }]

# Supply queries
proc get_supply(chain):
    return [true, {
        "total_supply": "10000000000000000000",
        "circulating_supply": _compute_circulating(chain),
        "mining_pool_remaining": chain.pool_remaining,
    }]

proc _compute_circulating(chain):
    let total = "0"
    for addr in chain.state.accounts:
        let acc = chain.state.accounts[addr]
        total = bi.bi_add(total, acc["balance"])
    return total