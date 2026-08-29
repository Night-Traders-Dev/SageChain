# orbit/api/rpc_server.sage — RPC Server Entry Point
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.api.rpc as rpcmod
import orbit.api.http as httpmod
import orbit.node.config as configmod
import orbit.ffi.io as ffi_io
import orbit.ffi.bindings as ffi

# Parse command line args
let args = ffi.ffi_get_args()
let config_path = "/etc/orbit/config.toml"
var i = 0
while i < len(args):
    if args[i] == "--config":
        config_path = args[i + 1]
        i = i + 2
    else:
        i = i + 1

# Load config
let config_result = configmod.load_config(config_path)
if not config_result[0]:
    ffi.ffi_log("error", "failed to load config: " + config_result[1])
    ffi.ffi_exit(1)
let config = config_result[1]

# Load chain from disk
let data_dir = config["storage"]["data_dir"]
let chain_path = data_dir + "/chain.json"

if not ffi_io.file_exists(chain_path):
    ffi.ffi_log("error", "chain not found at " + chain_path + ", run orbit-node first")
    ffi.ffi_exit(1)

import orbit.storage.persistent as persist
let chain_result = persist.load_chain(chain_path)
if not chain_result[0]:
    ffi.ffi_log("error", "failed to load chain: " + chain_result[1])
    ffi.ffi_exit(1)

let chain = chain_result[1]
let network_id = config["network"]["network_id"]

# Create RPC server
let server = httpmod.HTTPServer(config["rpc"]["listen_addr"])

# RPC endpoints
server.get("/status", proc(req):
    let tip = chain.tip()
    return httpmod.json_response({
        "height": tip.height,
        "tip_hash": tip.hash,
        "finalized_height": chain.finalized_height,
        "pool_remaining": chain.pool_remaining,
        "network_id": network_id,
    })
)

server.get("/network", proc(req):
    return httpmod.json_response({
        "network_id": network_id,
        "peer_count": 0,
    })
)

server.get("/blocks/latest", proc(req):
    let tip = chain.tip()
    return httpmod.json_response(tip)
)

server.get("/blocks/:height", proc(req):
    let height = int(req.params["height"])
    let blk = chain.get_block(height)
    if blk == nil:
        return httpmod.error_response("block not found", 404)
    return httpmod.json_response(blk)
)

server.get("/blocks/hash/:hash", proc(req):
    let hash = req.params["hash"]
    for blk in chain.blocks:
        if blk.hash == hash:
            return httpmod.json_response(blk)
    return httpmod.error_response("block not found", 404)
)

server.get("/tx/:txid", proc(req):
    let txid = req.params["txid"]
    for blk in chain.blocks:
        for t in blk.transactions:
            if t.tx_id == txid:
                return httpmod.json_response(t)
    return httpmod.error_response("tx not found", 404)
)

server.get("/address/:address", proc(req):
    let address = req.params["address"]
    let acc = chain.state.accounts[address]
    if acc == nil:
        return httpmod.error_response("address not found", 404)
    return httpmod.json_response({
        "address": address,
        "balance": acc["balance"],
        "nonce": acc["nonce"],
        "locked_balance": acc["locked_balance"],
        "activity_marker": acc["activity_marker"],
    })
)

server.get("/validators", proc(req):
    let out = []
    for addr in chain.validators.validators:
        let v = chain.validators.validators[addr]
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
    return httpmod.json_response(out)
)

server.get("/validators/:id", proc(req):
    let id = req.params["id"]
    let v = chain.validators.get(id)
    if v == nil:
        return httpmod.error_response("validator not found", 404)
    return httpmod.json_response({
        "address": v.address,
        "public_key": v.public_key,
        "activation_height": v.activation_height,
        "uptime_score": v.uptime_score,
        "trust_score": v.trust_score,
        "valid_vote_count": v.valid_vote_count,
        "invalid_vote_count": v.invalid_vote_count,
        "status": v.current_status,
    })
)

server.get("/mining/rate", proc(req):
    let tip = chain.tip()
    import orbit.mining.rate as mining_rate
    let rate = mining_rate.calculate_mining_rate(
        10000, chain.pool_remaining, tip.height, 500000)
    return httpmod.json_response({"rate": rate, "pool_remaining": chain.pool_remaining})
)

server.get("/supply", proc(req):
    return httpmod.json_response({
        "total_supply": "10000000000000000000",
        "circulating_supply": "0",
        "mining_pool_remaining": chain.pool_remaining,
    })
)

server.post("/tx", proc(req):
    if req.parsed_body == nil:
        return httpmod.error_response("missing body", 400)
    import orbit.core.transaction as txmod
    import orbit.crypto.encoding as enc

    let tx_json = req.parsed_body
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

    let vr = txmod.validate(tx, chain.state.accounts, chain.pool_remaining)
    if not vr[0]:
        return httpmod.error_response(vr[1], 400)
    return httpmod.json_response({"tx_id": tx.tx_id, "status": "pending"})
)

# Start server
ffi.ffi_log("info", "starting RPC server on " + config["rpc"]["listen_addr"])
let start_result = server.start()
if not start_result[0]:
    ffi.ffi_log("error", "failed to start RPC server: " + start_result[1])
    ffi.ffi_exit(1)

ffi.ffi_log("info", "RPC server started on " + config["rpc"]["listen_addr"])

# Keep running
while true:
    ffi.ffi_sleep_ms(1000)