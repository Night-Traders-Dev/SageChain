# orbit/api/http.sage — HTTP server for RPC & Explorer (§31)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.api.rpc as rpcmod
import orbit.crypto.encoding as enc
import orbit.mining.rate as mining_rate

let DEFAULT_PORT = 8333

class HTTPServer:
    proc init(self, chain, port = DEFAULT_PORT):
        self.chain = chain
        self.port = port
        self.rpc = rpcmod.RPCServer(chain)
        self.routes = {}
        self._register_routes()

    proc _register_routes(self):
        # RPC endpoints - using bound method references
        self.routes["GET:/status"] = self._status
        self.routes["GET:/network"] = self._network
        self.routes["GET:/blocks/latest"] = self._block_latest
        self.routes["GET:/mining/rate"] = self._mining_rate
        self.routes["GET:/supply"] = self._supply
        self.routes["GET:/validators"] = self._validators

        # Explorer endpoints
        self.routes["GET:/explorer/blocks"] = self._explorer_blocks
        self.routes["GET:/explorer/txs"] = self._explorer_txs
        self.routes["GET:/explorer/validators"] = self._explorer_validators
        self.routes["GET:/explorer/mining/stats"] = self._explorer_mining_stats
        self.routes["GET:/explorer/network/health"] = self._explorer_network_health

    proc _parse_path_with_param(self, path, prefix):
        if path.startswith(prefix):
            let param = slice(path, len(prefix))
            return param
        return nil

    proc handle_request(self, method, path, body = nil, query = nil):
        let key = method + ":" + path
        if dict_has(self.routes, key):
            return self.routes[key](query, body)

        # Parameterized routes
        if method == "GET":
            if path.startswith("/blocks/") and path != "/blocks/latest":
                let h = slice(path, 8)
                if h.startswith("hash/"):
                    return self.rpc._block_by_hash(slice(h, 5))
                return self.rpc._block_by_height(int(h))
            if path.startswith("/tx/"):
                return self.rpc._tx_by_id(slice(path, 4))
            if path.startswith("/address/"):
                return self.rpc._address(slice(path, 9))
            if path.startswith("/validators/") and path != "/validators":
                return self.rpc._validator_by_id(slice(path, 12))

            # Explorer parameterized
            if path.startswith("/explorer/address/"):
                return self._explorer_address(slice(path, 18))

        if method == "POST" and path == "/tx":
            return self.rpc._submit_tx(body)

        return [false, "not_found"]

    # RPC methods (bound)
    proc _status(self, q, b):
        return self.rpc._status()
    proc _network(self, q, b):
        return self.rpc._network()
    proc _block_latest(self, q, b):
        return self.rpc._block_latest()
    proc _mining_rate(self, q, b):
        return self.rpc._mining_rate()
    proc _supply(self, q, b):
        return self.rpc._supply()
    proc _validators(self, q, b):
        return self.rpc._validators()

    # Explorer methods (bound)
    proc _explorer_blocks(self, query, body):
        let page = 0
        let limit = 20
        if query != nil and query["page"] != nil:
            page = int(query["page"])
        if query != nil and query["limit"] != nil:
            limit = int(query["limit"])
        let start = self.chain.height() - page * limit
        let end = max(0, start - limit + 1)
        let blocks = []
        var h = start
        while h >= end and h >= 0:
            let blk = self.chain.get_block(h)
            if blk != nil:
                push(blocks, {
                    "height": blk.height,
                    "hash": blk.hash,
                    "timestamp": blk.timestamp,
                    "proposer": blk.proposer,
                    "tx_count": len(blk.transactions),
                    "finalized": h <= self.chain.finalized_height,
                })
            h = h - 1
        return [true, {"blocks": blocks, "page": page, "limit": limit, "total": self.chain.height() + 1}]

    proc _explorer_txs(self, query, body):
        let page = 0
        let limit = 50
        if query != nil and query["page"] != nil:
            page = int(query["page"])
        if query != nil and query["limit"] != nil:
            limit = int(query["limit"])
        let txs = []
        let count = 0
        var h = self.chain.height()
        while h >= 0 and count < (page + 1) * limit:
            let blk = self.chain.get_block(h)
            if blk != nil:
                for t in blk.transactions:
                    if count >= page * limit and count < (page + 1) * limit:
                        push(txs, {
                            "tx_id": t.tx_id,
                            "block_height": blk.height,
                            "kind": t.kind,
                            "sender": t.sender,
                            "recipient": t.recipient,
                            "amount": t.amount,
                            "fee": t.fee,
                            "timestamp": t.timestamp,
                        })
                    count = count + 1
            h = h - 1
        return [true, {"transactions": txs, "page": page, "limit": limit, "total": count}]

    proc _explorer_address(self, address, body):
        let acc = self.chain.state.accounts[address]
        if acc == nil:
            return [false, "address not found"]
        let recent_txs = []
        var h = self.chain.height()
        var found = 0
        while h >= 0 and found < 20:
            let blk = self.chain.get_block(h)
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
        return [true, {
            "address": address,
            "balance": acc["balance"],
            "nonce": acc["nonce"],
            "locked_balance": acc["locked_balance"],
            "activity_marker": acc["activity_marker"],
            "recent_transactions": recent_txs,
        }]

    proc _explorer_validators(self, query, body):
        let out = []
        for addr in self.chain.validators.validators:
            let v = self.chain.validators.validators[addr]
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

    proc _explorer_mining_stats(self, query, body):
        let tip = self.chain.tip()
        let rate = mining_rate.calculate_mining_rate(
            10000, self.chain.pool_remaining, tip.height, 500000)
        let blocks = []
        var h = tip.height
        while h >= max(0, tip.height - 100):
            let blk = self.chain.get_block(h)
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
            "pool_remaining": self.chain.pool_remaining,
            "pool_exhausted_pct": int((1000000 * (100000000000000000 - self.chain.pool_remaining)) / 100000000000000000),
            "recent_rewards": blocks,
        }]

    proc _explorer_network_health(self, query, body):
        return [true, {
            "height": self.chain.height(),
            "finalized_height": self.chain.finalized_height,
            "finality_lag": self.chain.height() - self.chain.finalized_height,
            "validator_count": self.chain.validators.active_count(),
            "peer_count": 0,
            "pool_remaining": self.chain.pool_remaining,
        }]

proc start_server(chain, port = DEFAULT_PORT):
    let server = HTTPServer(chain, port)
    print("Orbit RPC/Explorer HTTP server would start on port " + str(port))
    print("Endpoints:")
    print("  GET  /status")
    print("  GET  /network")
    print("  GET  /blocks/latest")
    print("  GET  /blocks/<height>")
    print("  GET  /blocks/hash/<hash>")
    print("  GET  /tx/<txid>")
    print("  GET  /address/<address>")
    print("  GET  /validators")
    print("  GET  /validators/<id>")
    print("  GET  /mining/rate")
    print("  GET  /supply")
    print("  POST /tx")
    print("  GET  /explorer/blocks?page=0&limit=20")
    print("  GET  /explorer/txs?page=0&limit=50")
    print("  GET  /explorer/address/<address>")
    print("  GET  /explorer/validators")
    print("  GET  /explorer/mining/stats")
    print("  GET  /explorer/network/health")
    return server