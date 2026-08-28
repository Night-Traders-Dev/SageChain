# orbit/core/ledger.sage — deterministic state transition engine (plan §4)
# Orbit Blockchain | Protocol v1 | Status: implemented (transfer/reward)
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
