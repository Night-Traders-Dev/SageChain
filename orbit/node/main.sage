# orbit/node/main.sage — Orbit Node Entry Point
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.node.config as configmod
import orbit.node.bootstrap as bootstrap
import orbit.node.service as servicemod
import orbit.api.http as httpmod
import orbit.mining.miner as minermod
import orbit.ffi.net as ffi_net
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

# Bootstrap node
let result = bootstrap.bootstrap_node(config_path)
if not result[0]:
    ffi.ffi_log("error", "bootstrap failed: " + result[1])
    ffi.ffi_exit(1)

let ctx = result[1]
let chain = ctx["chain"]
let config = ctx["config"]
let services = ctx["services"]
let network = ctx["network"]

# Start all services
let node_service = services["node"]
let miner_service = services["miner"]
let rpc_service = services["rpc"]
let explorer_service = services["explorer"]

ffi.ffi_log("info", "starting node service...")
let node_start = node_service.start()
if not node_start[0]:
    ffi.ffi_log("error", "node service failed to start: " + node_service.service.error)
    ffi.ffi_exit(1)

ffi.ffi_log("info", "starting miner service...")
let miner_start = miner_service.start()
if not miner_start[0]:
    ffi.ffi_log("error", "miner service failed to start: " + miner_service.service.error)

ffi.ffi_log("info", "starting rpc service...")
let rpc_start = rpc_service.start()
if not rpc_start[0]:
    ffi.ffi_log("error", "rpc service failed to start: " + rpc_service.service.error)

ffi.ffi_log("info", "starting explorer service...")
let explorer_start = explorer_service.start()
if not explorer_start[0]:
    ffi.ffi_log("error", "explorer service failed to start: " + explorer_service.service.error)

ffi.ffi_log("info", "all services started successfully")

# Keep main process alive
while true:
    ffi.ffi_sleep_ms(1000)

    # Periodic chain persistence
    import orbit.storage.persistent as persist
    let chain_path = config["storage"]["data_dir"] + "/chain.json"
    let save_result = persist.save_chain(chain, chain_path)
    if not save_result[0]:
        ffi.ffi_log("warn", "failed to save chain: " + save_result[1])

    # Health check
    let node_status = node_service.get_status()
    if node_status["status"] != "running":
        ffi.ffi_log("error", "node service stopped unexpectedly")
        break