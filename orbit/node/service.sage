# orbit/node/service.sage — service framework
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.core.chain as chainmod
import orbit.node.config as configmod
import orbit.storage.persistent as persist

# Service status enum
let SERVICE_STOPPED = "stopped"
let SERVICE_STARTING = "starting"
let SERVICE_RUNNING = "running"
let SERVICE_STOPPING = "stopping"
let SERVICE_ERROR = "error"

class Service:
    proc init(self, name):
        self.name = name
        self.status = SERVICE_STOPPED
        self.error = nil
        self.start_time = 0

    proc start(self):
        self.status = SERVICE_STARTING
        let ok = self.on_start()
        if ok:
            self.status = SERVICE_RUNNING
            self.start_time = self.get_timestamp()
        else:
            self.status = SERVICE_ERROR
        return ok

    proc stop(self):
        self.status = SERVICE_STOPPING
        let ok = self.on_stop()
        self.status = SERVICE_STOPPED
        return ok

    proc restart(self):
        self.stop()
        return self.start()

    proc get_status(self):
        let uptime = 0
        if self.start_time > 0:
            uptime = self.get_timestamp() - self.start_time
        return {
            "name": self.name,
            "status": self.status,
            "uptime": uptime,
            "error": self.error,
        }

    proc on_start(self):
        return true

    proc on_stop(self):
        return true

    proc get_timestamp(self):
        # Placeholder - needs actual timestamp
        return 0

# Node service - manages the blockchain
class NodeService:
    proc init(self, config):
        self.config = config
        self.chain = nil
        self.service = Service("node")
        self.running = false

    proc start(self):
        let ok = self.service.start()
        if not ok:
            return false

        # Load or create chain
        let genesis_path = self.config["storage"]["data_dir"] + "/genesis.json"
        let chain_path = self.config["storage"]["data_dir"] + "/chain.json"

        if persist.file_exists(genesis_path):
            let genesis = persist.load_genesis(genesis_path)
        else:
            let genesis = configmod.default_genesis()
            persist.save_genesis(genesis, genesis_path)

        if persist.file_exists(chain_path):
            self.chain = persist.load_chain(chain_path)
        else:
            self.chain = chainmod.Chain(self.config["network"]["network_id"])
            # Save initial chain
            persist.save_chain(self.chain, chain_path)

        # Load validator keystore if validator enabled
        if self.config["validator"]["enabled"]:
            self.load_validator_keystore()

        self.running = true
        return true

    proc stop(self):
        self.running = false
        if self.chain != nil:
            let chain_path = self.config["storage"]["data_dir"] + "/chain.json"
            persist.save_chain(self.chain, chain_path)
        return self.service.stop()

    proc load_validator_keystore(self):
        let ks_path = self.config["validator"]["keystore_path"]
        let password = self.config["validator"]["password"]
        # Load and register validator
        pass

    proc get_chain(self):
        return self.chain

    proc get_status(self):
        let base = self.service.get_status()
        if self.chain != nil:
            base["chain_height"] = self.chain.height()
            base["finalized_height"] = self.chain.finalized_height
            base["pool_remaining"] = self.chain.pool_remaining
        return base

# Miner service - handles block production
class MinerService:
    proc init(self, node_service, config):
        self.node = node_service
        self.config = config
        self.service = Service("miner")
        self.running = false
        self.current_block = nil

    proc start(self):
        if not self.config["mining"]["enabled"]:
            self.service.error = "mining disabled in config"
            self.service.status = SERVICE_ERROR
            return false

        if self.node.chain == nil:
            self.service.error = "node not started"
            self.service.status = SERVICE_ERROR
            return false

        let ok = self.service.start()
        if not ok:
            return false

        self.running = true
        return true

    proc stop(self):
        self.running = false
        return self.service.stop()

    # Main mining loop - called from external scheduler
    proc mine_once(self):
        if not self.running:
            return false

        let chain = self.node.chain
        let proposer = self.get_proposer_address()

        # Assemble block with pending transactions
        let txs = self.get_pending_transactions()
        let asm = chain.assemble_block(proposer, self.get_timestamp(), txs, nil)
        if not asm[0]:
            return false

        let apply_result = chain.apply_assembled(asm)
        if not apply_result[0]:
            return false

        # Broadcast block (placeholder)
        self.broadcast_block(chain.tip())

        return true

    proc get_proposer_address(self):
        # Return validator address or genesis
        return "genesis"

    proc get_pending_transactions(self):
        # Return pending transactions from mempool
        return []

    proc get_timestamp(self):
        return 0

    proc broadcast_block(self, block):
        # Placeholder for P2P broadcast
        pass

    proc get_status(self):
        let base = self.service.get_status()
        base["blocks_mined"] = 0  # would track
        return base

# RPC service - HTTP JSON-RPC server
class RPCService:
    proc init(self, node_service, config):
        self.node = node_service
        self.config = config
        self.service = Service("rpc")
        self.server = nil

    proc start(self):
        if not self.config["rpc"]["enabled"]:
            self.service.error = "rpc disabled in config"
            self.service.status = SERVICE_ERROR
            return false

        let ok = self.service.start()
        if not ok:
            return false

        # Start HTTP server (placeholder - needs actual HTTP server)
        self.start_http_server()
        return true

    proc stop(self):
        if self.server != nil:
            self.stop_http_server()
        return self.service.stop()

    proc start_http_server(self):
        # Placeholder - needs actual HTTP server implementation
        print("RPC HTTP server would start on " + self.config["rpc"]["listen_addr"])

    proc stop_http_server(self):
        pass

    proc handle_request(self, method, path, body):
        # Delegate to existing RPC implementation
        import orbit.api.rpc as rpcmod
        let rpc = rpcmod.RPCService(self.node.chain)
        return rpc.handle_request(method, path, body)

    proc get_status(self):
        let base = self.service.get_status()
        base["endpoint"] = self.config["rpc"]["listen_addr"]
        return base

# Explorer service - HTTP server for block explorer
class ExplorerService:
    proc init(self, node_service, config):
        self.node = node_service
        self.config = config
        self.service = Service("explorer")
        self.server = nil

    proc start(self):
        if not self.config["explorer"]["enabled"]:
            self.service.error = "explorer disabled in config"
            self.service.status = SERVICE_ERROR
            return false

        let ok = self.service.start()
        if not ok:
            return false

        self.start_http_server()
        return true

    proc stop(self):
        if self.server != nil:
            self.stop_http_server()
        return self.service.stop()

    proc start_http_server(self):
        print("Explorer HTTP server would start on " + self.config["explorer"]["listen_addr"])

    proc stop_http_server(self):
        pass

    proc get_status(self):
        let base = self.service.get_status()
        base["endpoint"] = self.config["explorer"]["listen_addr"]
        return base