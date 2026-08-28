# orbit/consensus/validator.sage — validator registry & lifecycle (plan §16)
# Orbit Blockchain | Protocol v1 | Status: implemented (v1 rules)
#
# Lifecycle: register (min self-stake locked) -> ACTIVE -> (penalty threshold)
#            SLASHED/INACTIVE. Pending validators carry zero vote weight.
#
# Anti-gaming (§12): bounded initial score, gradual accrual, faster penalties,
# self-stake requirement so Sybil identities start weightless.

import orbit.core.bigint as bi
import orbit.core.errors as errors
import orbit.crypto.encoding as encoding
from crypto.hash import sha256_hex

let INITIAL_TRUST = 250000        # 0.25 on the 10^6 grid — bounded start
let MIN_SELF_STAKE = "100000000000"   # 1000 ORBIT in base units, self-locked
let PENALTY_SLASH_LIMIT = 600000  # penalty_points reaching this deactivates

proc new_validator(validator_id, public_key):
    return {
        "validator_id": validator_id,
        "public_key": public_key,
        "activation_height": 0,
        "last_seen_height": 0,
        "uptime_score": 0,
        "trust_score": INITIAL_TRUST,
        "valid_vote_count": 0,
        "invalid_vote_count": 0,
        "proposed_blocks": 0,
        "accepted_blocks": 0,
        "penalty_points": 0,
        "current_status": "pending",
    }

class ValidatorRegistry:
    proc init(self):
        self.validators = {}     # address -> validator record

    proc has(self, addr):
        return dict_has(self.validators, addr)

    proc get(self, addr):
        return self.validators[addr]

    proc active_count(self):
        let n = 0
        for addr in self.validators:
            if self.validators[addr]["current_status"] == "active":
                n = n + 1
        return n

    proc clone(self):
        let copy = ValidatorRegistry()
        for addr in self.validators:
            let v = self.validators[addr]
            let c = new_validator(v["validator_id"], v["public_key"])
            for field in ["activation_height", "last_seen_height", "uptime_score",
                          "trust_score", "valid_vote_count", "invalid_vote_count",
                          "proposed_blocks", "accepted_blocks", "penalty_points",
                          "current_status"]:
                c[field] = v[field]
            copy.validators[addr] = c
        return copy

    # Register with self-stake. Moves `stake` from balance to locked_balance
    # and activates when the minimum is met. Deterministic; idempotent-fail.
    proc register(self, state, addr, public_key, stake, height):
        # `state` may be a WorldState instance or a bare {accounts:{...}} map
        var accounts = nil
        if type(state) == "dict":
            accounts = state["accounts"]
        else:
            accounts = state.accounts
        if not dict_has(accounts, addr):
            return [false, errors.ERR_INVALID_TX]
        if dict_has(self.validators, addr):
            return [false, errors.ERR_INVALID_TX]
        let acct = accounts[addr]
        if bi.bi_cmp(acct["balance"], stake) < 0:
            return [false, errors.ERR_INSUFFICIENT]

        acct["balance"] = bi.bi_sub(acct["balance"], stake)
        acct["locked_balance"] = bi.bi_add(acct["locked_balance"], stake)
        acct["validator_status"] = "validator"

        let rec = new_validator(addr, public_key)
        rec["activation_height"] = height
        rec["last_seen_height"] = height
        if bi.bi_cmp(stake, MIN_SELF_STAKE) >= 0:
            rec["current_status"] = "active"
        push_key_commitment(rec)
        self.validators[addr] = rec
        return [true, nil]

    proc slash_or_deactivate(self, addr, height):
        let v = self.validators[addr]
        v["current_status"] = "slashed"
        v["last_seen_height"] = height

    proc root(self):
        # validator_root commitment (§20): merkle over canonical records of
        # ACTIVE validators, sorted by address.
        import orbit.core.merkle as merkle
        let addrs = []
        for addr in self.validators:
            if self.validators[addr]["current_status"] == "active":
                push(addrs, addr)
        let sorted = encoding.sort_strings(addrs)
        let leaves = []
        for addr in sorted:
            push(leaves, sha256_hex(encoding.encode_canonical(
                [addr, self.validators[addr]["trust_score"],
                 self.validators[addr]["uptime_score"],
                 self.validators[addr]["current_status"]])))
        return merkle.root(leaves)

proc push_key_commitment(rec):
    # reserved hook: key rotation commitments land with ed25519 (Phase 2+)
    return rec
