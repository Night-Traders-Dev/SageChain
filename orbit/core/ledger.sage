# orbit/core/ledger.sage — deterministic state transition engine (plan §4)
# Orbit Blockchain | Protocol v1 | Status: implemented (transfer/reward/lockup)
#
# apply() MUST only be called after transaction.validate() succeeded.
# Deterministic order of mutations; no wall-clock reads anywhere.

import orbit.core.bigint as bi

class Ledger:
    proc init(self, world_state):
        self.state = world_state

    proc apply(self, tx, pool_remaining):
        # returns [ok, err, updated_pool_remaining]
        if tx.kind == "reward":
            let pool_after = bi.bi_sub(pool_remaining, tx.amount)
            let acct = self.state.get(tx.recipient)
            acct["balance"] = bi.bi_add(acct["balance"], tx.amount)
            acct["activity_marker"] = tx.timestamp
            return [true, nil, pool_after]

        if tx.kind == "lock":
            return self.apply_lock(tx, pool_remaining)
        if tx.kind == "unlock":
            return self.apply_unlock(tx, pool_remaining)
        if tx.kind == "claim":
            return self.apply_claim(tx, pool_remaining)

        # transfer
        let sender_acct = self.state.get(tx.sender)
        let spend = bi.bi_add(tx.amount, tx.fee)
        sender_acct["balance"] = bi.bi_sub(sender_acct["balance"], spend)
        sender_acct["nonce"] = sender_acct["nonce"] + 1
        sender_acct["activity_marker"] = tx.timestamp

        let recv_acct = self.state.get(tx.recipient)
        recv_acct["balance"] = bi.bi_add(recv_acct["balance"], tx.amount)
        recv_acct["activity_marker"] = tx.timestamp

        # fee burn is intentional in v1 (nodefeecollector wiring is Phase 5+)
        return [true, nil, pool_remaining]

    proc apply_lock(self, tx, pool_remaining):
        let acct = self.state.get(tx.sender)
        let spend = bi.bi_add(tx.amount, tx.fee)
        acct["balance"] = bi.bi_sub(acct["balance"], spend)
        acct["locked_balance"] = bi.bi_add(acct["locked_balance"], tx.amount)
        acct["nonce"] = acct["nonce"] + 1
        acct["activity_marker"] = tx.timestamp
        # Create lockup position
        if acct["lockups"] == nil:
            acct["lockups"] = {}
        acct["lockups"][tx.lockup_id] = {
            "amount": tx.amount,
            "lock_height": str(tx.timestamp),
            "claim_height": str(tx.claim_height),
            "lock_duration": str(tx.lock_duration),
            "claimed": false,
            "status": "LOCKED",
        }
        return [true, nil, pool_remaining]

    proc apply_unlock(self, tx, pool_remaining):
        let acct = self.state.get(tx.sender)
        if acct["lockups"] == nil or acct["lockups"][tx.lockup_id] == nil:
            return [false, "lockup_not_found", pool_remaining]
        let lockup = acct["lockups"][tx.lockup_id]
        if lockup["status"] != "LOCKED":
            return [false, "lockup_not_locked", pool_remaining]
        # Check if unlock is allowed (after lock duration)
        let current_height = tx.timestamp
        let lock_height = int(lockup["lock_height"])
        let lock_duration = int(lockup["lock_duration"])
        if current_height < lock_height + lock_duration:
            return [false, "lock_duration_not_met", pool_remaining]
        # Move from locked to available
        acct["locked_balance"] = bi.bi_sub(acct["locked_balance"], lockup["amount"])
        acct["balance"] = bi.bi_add(acct["balance"], lockup["amount"])
        lockup["status"] = "UNLOCKED"
        acct["nonce"] = acct["nonce"] + 1
        acct["activity_marker"] = tx.timestamp
        return [true, nil, pool_remaining]

    proc apply_claim(self, tx, pool_remaining):
        let acct = self.state.get(tx.sender)
        if acct["lockups"] == nil or acct["lockups"][tx.lockup_id] == nil:
            return [false, "lockup_not_found", pool_remaining]
        let lockup = acct["lockups"][tx.lockup_id]
        if lockup["status"] != "LOCKED" and lockup["status"] != "CLAIMABLE":
            return [false, "lockup_not_claimable", pool_remaining]
        let current_height = tx.timestamp
        let claim_height = int(lockup["claim_height"])
        if current_height < claim_height:
            return [false, "claim_not_ready", pool_remaining]
        # Calculate lockup reward (deterministic per-block APR equivalent)
        let reward = self.calculate_lockup_reward(lockup, current_height)
        if bi.bi_cmp(reward, "0") > 0:
            acct["balance"] = bi.bi_add(acct["balance"], reward)
            # Reward comes from lockup_rewards pool (genesis allocation)
            # For v1, we track it in the account
        lockup["claimed"] = true
        lockup["status"] = "CLAIMED"
        acct["nonce"] = acct["nonce"] + 1
        acct["activity_marker"] = tx.timestamp
        return [true, nil, pool_remaining]

    # Lockup reward: 5% APR equivalent, calculated deterministically per block
    # 5% per year ≈ 5% / (365*24*60*60/block_time) per block
    # With 500 block_time seconds: blocks_per_year = 365*24*60*60/500 ≈ 63072
    # Rate per block = 0.05 / 63072 ≈ 7.93e-7 per block
    # Fixed-point: reward = amount * 5 * blocks_locked / (100 * blocks_per_year)
    proc calculate_lockup_reward(self, lockup, current_height):
        let BLOCKS_PER_YEAR = 63072
        let APR_NUMERATOR = 5  # 5%
        let APR_DENOMINATOR = 100
        let lock_height = int(lockup["lock_height"])
        let blocks_locked = current_height - lock_height
        if blocks_locked <= 0:
            return "0"
        # Fixed-point calculation
        let num = bi.bi_mul(lockup["amount"], bi.bi_from_number(APR_NUMERATOR * blocks_locked))
        let den = bi.bi_from_number(APR_DENOMINATOR * BLOCKS_PER_YEAR)
        let qr = bi.bi_divmod(num, den)
        return qr[0]