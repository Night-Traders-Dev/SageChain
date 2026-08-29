# orbit/api/explorer_server.sage — Explorer Server Entry Point
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.api.explorer as explore
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

# Create explorer HTTP server
let server = httpmod.HTTPServer(config["explorer"]["listen_addr"])

# Explorer endpoints
server.get("/health", proc(req):
    return httpmod.json_response({"status": "ok", "service": "explorer"})
)

server.get("/blocks", proc(req):
    let page = int(explore.get_query_param(req, "page", "0"))
    let limit = int(explore.get_query_param(req, "limit", "20"))
    let result = explore.list_blocks(chain, page, limit)
    return httpmod.json_response(result[1])
)

server.get("/blocks/:height", proc(req):
    let height = int(req.params["height"])
    let result = explore.get_block_by_height(chain, height)
    if not result[0]:
        return httpmod.error_response("block not found", 404)
    return httpmod.json_response(result[1])
)

server.get("/blocks/hash/:hash", proc(req):
    let hash = req.params["hash"]
    let result = explore.get_block_by_hash(chain, hash)
    if not result[0]:
        return httpmod.error_response("block not found", 404)
    return httpmod.json_response(result[1])
)

server.get("/txs", proc(req):
    let page = int(explore.get_query_param(req, "page", "0"))
    let limit = int(explore.get_query_param(req, "limit", "50"))
    let result = explore.list_txs(chain, page, limit)
    return httpmod.json_response(result[1])
)

server.get("/txs/:txid", proc(req):
    let txid = req.params["txid"]
    let result = explore.get_tx_by_id(chain, txid)
    if not result[0]:
        return httpmod.error_response("tx not found", 404)
    return httpmod.json_response(result[1])
)

server.get("/address/:address", proc(req):
    let address = req.params["address"]
    let result = explore.get_address(chain, address)
    if not result[0]:
        return httpmod.error_response("address not found", 404)
    return httpmod.json_response(result[1])
)

server.get("/address/:address/txs", proc(req):
    let address = req.params["address"]
    let limit = int(explore.get_query_param(req, "limit", "20"))
    let result = explore.get_address_txs(chain, address, limit)
    return httpmod.json_response(result[1])
)

server.get("/validators", proc(req):
    let result = explore.list_validators(chain)
    return httpmod.json_response(result[1])
)

server.get("/validators/:address", proc(req):
    let address = req.params["address"]
    let result = explore.get_validator(chain, address)
    if not result[0]:
        return httpmod.error_response("validator not found", 404)
    return httpmod.json_response(result[1])
)

server.get("/mining/stats", proc(req):
    let result = explore.get_mining_stats(chain)
    return httpmod.json_response(result[1])
)

server.get("/network/health", proc(req):
    let result = explore.get_network_health(chain)
    return httpmod.json_response(result[1])
)

server.get("/supply", proc(req):
    let result = explore.get_supply(chain)
    return httpmod.json_response(result[1])
)

# Start server
ffi.ffi_log("info", "starting Explorer server on " + config["explorer"]["listen_addr"])
let start_result = server.start()
if not start_result[0]:
    ffi.ffi_log("error", "failed to start Explorer server: " + start_result[1])
    ffi.ffi_exit(1)

ffi.ffi_log("info", "Explorer server started on " + config["explorer"]["listen_addr"])

# Keep running
while true:
    ffi.ffi_sleep_ms(1000)

    # Periodic chain persistence
    import orbit.storage.persistent as persist
    let chain_path = config["storage"]["data_dir"] + "/chain.json"
    let save_result = persist.save_chain(chain, chain_path)
    if not save_result[0]:
        ffi.ffi_log("warn", "failed to save chain: " + save_result[1])