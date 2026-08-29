# orbit/core/state.sage — account state + deterministic state root (plan §19)
# Orbit Blockchain | Protocol v1 | Status: implemented
#
# WorldState is a plain dict: address -> account record. The state root is a
# merkle commitment over canonical per-account encodings, addresses sorted.

import orbit.core.bigint as bi
import orbit.core.merkle as merkle
import orbit.crypto.encoding as encoding
from crypto.hash import sha256_hex

proc new_account(address):
    return {
        "balance": "0",
        "nonce": 0,
        "locked_balance": "0",
        "activity_marker": 0,
        "validator_status": nil,
        "lockups": {},
    }

class WorldState:
    proc init(self):
        self.accounts = {}
        self.contracts = {}

    proc get(self, address):
        if not dict_has(self.accounts, address):
            self.accounts[address] = new_account(address)
        return self.accounts[address]

    proc has(self, address):
        return dict_has(self.accounts, address)

    proc clone(self):
        let copy = WorldState()
        for addr in self.accounts:
            let a = self.accounts[addr]
            copy.accounts[addr] = {
                "balance": a["balance"],
                "nonce": a["nonce"],
                "locked_balance": a["locked_balance"],
                "activity_marker": a["activity_marker"],
                "validator_status": a["validator_status"],
                "lockups": a["lockups"],
            }
        for addr in self.contracts:
            copy.contracts[addr] = self.contracts[addr]
        return copy

    proc state_root(self):
        # leaves: sha256(canonical([address, balance, nonce, locked, activity, lockups]))
        let addrs = []
        for addr in self.accounts:
            push(addrs, addr)
        let sorted = encoding.sort_strings(addrs)
        let leaves = []
        for addr in sorted:
            let a = self.accounts[addr]
            # Include lockups in state root
            let lockups_encoded = []
            if a["lockups"] != nil:
                let lockup_ids = []
                for lid in a["lockups"]:
                    push(lockup_ids, lid)
                let sorted_lids = encoding.sort_strings(lockup_ids)
                for lid in sorted_lids:
                    let l = a["lockups"][lid]
                    push(lockups_encoded, [lid, l["amount"], l["lock_height"], l["claim_height"], l["lock_duration"], l["claimed"], l["status"]])
            push(leaves, sha256_hex(encoding.encode_canonical(
                [addr, a["balance"], a["nonce"], a["locked_balance"], a["activity_marker"], lockups_encoded]
            )))
        return merkle.root(leaves)
