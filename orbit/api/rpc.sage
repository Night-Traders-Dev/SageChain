# orbit/api/rpc.sage — local JSON/RPC API (§31)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.core.chain as chainmod
import orbit.core.block as blockmod
import orbit.core.transaction as txmod
import orbit.core.state as statemod
import orbit.consensus.validator as validatormod
import orbit.consensus.finality as finalitymod
import orbit.mining.rate as mining_rate
import orbit.wallet.wallet as wallet
import orbit.crypto.encoding as enc
from crypto.hash import sha256_hex

class RPCServer:
    proc init(self, chain):
        self.chain = chain

    proc handle_request(self, method, path, body = nil):
        if method == "GET":
            if path == "/status":
                return self._status()
            if path == "/network":
                return self._network()
            if path == "/blocks/latest":
                return self._block_latest()
            if path.startswith("/blocks/") and path != "/blocks/latest":
                let h = slice(path, 8)
                if h.startswith("hash/"):
                    return self._block_by_hash(slice(h, 5))
                return self._block_by_height(int(h))
            if path.startswith("/tx/"):
                return self._tx_by_id(slice(path, 4))
            if path.startswith("/address/"):
                return self._address(slice(path, 9))
            if path == "/validators":
                return self._validators()
            if path.startswith("/validators/"):
                return self._validator_by_id(slice(path, 12))
            if path == "/mining/rate":
                return self._mining_rate()
            if path == "/supply":
                return self._supply()
        if method == "POST":
            if path == "/tx":
                return self._submit_tx(body)
        return [false, "not_found"]

    proc _status(self):
        let tip = self.chain.tip()
        return [true, {
            "height": tip.height,
            "tip_hash": tip.hash,
            "finalized_height": self.chain.finalized_height,
            "pool_remaining": self.chain.pool_remaining,
            "network_id": self.chain.network_id,
        }]

    proc _network(self):
        return [true, {
            "network_id": self.chain.network_id,
            "peer_count": 0,
        }]

    proc _block_latest(self):
        let tip = self.chain.tip()
        return [true, self._block_to_json(tip)]

    proc _block_by_height(self, height):
        let blk = self.chain.get_block(height)
        if blk == nil:
            return [false, "block not found"]
        return [true, self._block_to_json(blk)]

    proc _block_by_hash(self, hash):
        for blk in self.chain.blocks:
            if blk.hash == hash:
                return [true, self._block_to_json(blk)]
        return [false, "block not found"]

    proc _block_to_json(self, blk):
        let txs = []
        for t in blk.transactions:
            push(txs, txmod.canonical_fields(t))
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
            "transactions": txs,
        }

    proc _tx_by_id(self, txid):
        for blk in self.chain.blocks:
            for t in blk.transactions:
                if t.tx_id == txid:
                    return [true, txmod.canonical_fields(t)]
        return [false, "tx not found"]

    proc _address(self, address):
        let acc = self.chain.state.accounts[address]
        if acc == nil:
            return [false, "address not found"]
        return [true, {
            "address": address,
            "balance": acc["balance"],
            "nonce": acc["nonce"],
            "locked_balance": acc["locked_balance"],
            "activity_marker": acc["activity_marker"],
        }]

    proc _validators(self):
        let out = []
        for addr in self.chain.validators.validators:
            let v = self.chain.validators.validators[addr]
            push(out, {
                "address": v.address,
                "public_key": v.public_key,
                "activation_height": v.activation_height,
                "uptime_score": v.uptime_score,
                "trust_score": v.trust_score,
                "valid_vote_count": v.valid_vote_count,
                "invalid_vote_count": v.invalid_vote_count,
                "status": v.current_status,
            })
        return [true, out]

    proc _validator_by_id(self, id):
        let v = self.chain.validators.get(id)
        if v == nil:
            return [false, "validator not found"]
        return [true, {
            "address": v.address,
            "public_key": v.public_key,
            "activation_height": v.activation_height,
            "uptime_score": v.uptime_score,
            "trust_score": v.trust_score,
            "valid_vote_count": v.valid_vote_count,
            "invalid_vote_count": v.invalid_vote_count,
            "status": v.current_status,
        }]

    proc _mining_rate(self):
        let tip = self.chain.tip()
        let rate = mining_rate.calculate_mining_rate(
            10000,  # users - would come from active user count
            self.chain.pool_remaining,
            tip.height,
            0.5  # score_scaled - would come from validator
        )
        return [true, {"rate": rate, "pool_remaining": self.chain.pool_remaining}]

    proc _supply(self):
        return [true, {
            "total_supply": "10000000000000000000",
            "circulating_supply": "0",  # would compute from state
            "mining_pool_remaining": self.chain.pool_remaining,
        }]

    proc _submit_tx(self, body):
        if body == nil:
            return [false, "missing body"]
        let tx_json = enc.decode_canonical(body)
        let tx = txmod.Transaction(
            tx_json["kind"],
            tx_json["sender"],
            tx_json["recipient"],
            tx_json["amount"],
            tx_json["fee"],
            tx_json["nonce"],
            tx_json["timestamp"]
        )
        tx.signature = tx_json["signature"]
        tx.tx_id = tx_json["tx_id"]
        if tx_json["memo"] != nil:
            tx.memo = tx_json["memo"]
        let vr = txmod.validate(tx, self.chain.state.accounts, self.chain.pool_remaining)
        if not vr[0]:
            return [false, vr[1]]
        return [true, {"tx_id": tx.tx_id, "status": "pending"}]