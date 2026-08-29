# orbit/node/bootstrap.sage — genesis/config loading and node initialization
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.node.config as configmod
import orbit.storage.persistent as persist
import orbit.ffi.io as ffi_io
import orbit.core.chain as chainmod
import orbit.core.genesis as genesis

# ============================================================
# BOOTSTRAP SEQUENCE
# ============================================================

# Full node initialization from config file
# Returns: [ok, {chain, config, services}_or_error]
proc bootstrap_node(config_path):
    # 1. Load config
    let config_result = configmod.load_config(config_path)
    if not config_result[0]:
        return config_result
    let config = config_result[1]

    # Merge with defaults
    let defaults = configmod.default_config()
    config = deep_merge(defaults, config)

    # 2. Ensure data directory exists
    let data_dir = config["storage"]["data_dir"]
    let mkdir_result = ffi_io.mkdir_p(data_dir)
    if not mkdir_result[0]:
        return [false, "failed to create data dir: " + mkdir_result[1]]

    # 3. Load or create genesis
    let genesis_path = data_dir + "/genesis.json"
    let chain = nil

    if ffi_io.file_exists(genesis_path):
        let genesis_result = persist.load_genesis(genesis_path)
        if not genesis_result[0]:
            return [false, "failed to load genesis: " + genesis_result[1]]
        let genesis = genesis_result[1]
    else:
        let genesis = configmod.default_genesis()
        # Override with config if specified
        if dict_has(config, "genesis"):
            genesis = deep_merge(genesis, config["genesis"])
        let save_result = persist.save_genesis(genesis, genesis_path)
        if not save_result[0]:
            return [false, "failed to save genesis: " + save_result[1]]

    # 4. Load or create chain
    let chain_path = data_dir + "/chain.json"
    if ffi_io.file_exists(chain_path):
        let chain_result = persist.load_chain(chain_path)
        if not chain_result[0]:
            return [false, "failed to load chain: " + chain_result[1]]
        chain = chain_result[1]
    else:
        # Create new chain from genesis
        chain = chainmod.Chain(config["network"]["network_id"])
        # Apply genesis allocations
        let genesis_state = genesismod.build_genesis_state()
        for addr in genesis_state:
            chain.state.accounts[addr] = genesis_state[addr]

        # Save initial chain
        let save_result = persist.save_chain(chain, chain_path)
        if not save_result[0]:
            return [false, "failed to save initial chain: " + save_result[1]]

    # 4. Create services
    import orbit.node.service as servicemod
    import orbit.api.http as httpmod
    import orbit.mining.miner as minermod
    import orbit.ffi.net as ffi_net

    let node_service = servicemod.NodeService(config)
    node_service.chain = chain

    let miner_service = minermod.MinerService(chain, config["mining"])
    let rpc_service = httpmod.RPCService(chain)
    let explorer_service = httpmod.ExplorerService(chain)

    let network_transport = ffi_net.MemoryTransport("local", config["network"]["network_id"])

    # 5. Start services
    let services = {
        "node": node_service,
        "miner": miner_service,
        "rpc": rpc_service,
        "explorer": explorer_service,
    }

    return [true, {
        "chain": chain,
        "config": config,
        "services": services,
        "network": network_transport,
    }]

# ============================================================
# DEEP MERGE HELPER
# ============================================================

proc deep_merge(base, override):
    let result = {}
    for k in base:
        result[k] = base[k]
    for k in override:
        if dict_has(result, k) and type(result[k]) == "dict" and type(override[k]) == "dict":
            result[k] = deep_merge(result[k], override[k])
        else:
            result[k] = override[k]
    return result

# ============================================================
# GENESIS VALIDATION
# ============================================================

proc validate_genesis(genesis):
    # Check required fields
    let required = ["network_id", "chain_id", "timestamp", "allocations", "mining_params"]
    for field in required:
        if not dict_has(genesis, field):
            return [false, "missing required field: " + field]

    # Validate allocations sum
    let total = "0"
    import orbit.core.bigint as bi
    for name in genesis["allocations"]:
        total = bi.bi_add(total, genesis["allocations"][name])

    let expected = bi.bi_mul("100000000000", "100000000")  # 100B * 10^8
    if bi.bi_cmp(total, expected) != 0:
        return [false, "allocations don't sum to total supply"]

    # Validate mining params
    let mp = genesis["mining_params"]
    let required_mp = ["r_base", "u_target", "s_max", "b_halflife", "node_boost_max"]
    for field in required_mp:
        if not dict_has(mp, field):
            return [false, "missing mining param: " + field]

    return [true, nil]

# ============================================================
# NODE IDENTITY
# ============================================================

proc generate_node_id():
    import orbit.wallet.account as account
    import orbit.crypto.encoding as enc
    from crypto.hash import sha256_hex

    let seed = "orbit-node-" + str(ffi.ffi_time_now_ns()) + "-" + ffi.ffi_getpid()
    let kp = account.generate_keypair(seed)
    return kp["address"]

proc load_or_create_node_identity(data_dir):
    let identity_path = data_dir + "/node_identity.json"
    if ffi_io.file_exists(identity_path):
        let result = ffi_io.load_json(identity_path)
        if result[0]:
            return [true, result[1]]

    let node_id = generate_node_id()
    let identity = {
        "node_id": node_id,
        "created_at": ffi.ffi_time_now(),
    }
    let save_result = ffi_io.save_json(identity, identity_path)
    if not save_result[0]:
        return [false, "failed to save identity"]

    return [true, identity]

# ============================================================
# VALIDATOR KEYSTORE
# ============================================================

proc load_validator_keystore(config):
    if not config["validator"]["enabled"]:
        return [true, nil]

    let ks_path = config["validator"]["keystore_path"]
    let password = config["validator"]["password"]

    if not ffi_io.file_exists(ks_path):
        return [false, "validator keystore not found: " + ks_path]

    let result = ffi_io.load_json(ks_path)
    if not result[0]:
        return result

    # Decrypt keystore
    import orbit.wallet.keystore as keystore
    let decrypted = keystore.load_keystore(result[1], password)
    return [true, decrypted]

proc create_validator_keystore(config, seed):
    import orbit.wallet.keystore as keystore
    import orbit.wallet.account as account

    let kp = account.generate_keypair(seed)
    let ks_data = {"wallets": [keystore.create_wallet_entry("validator", seed)]}
    let password = config["validator"]["password"]

    let encrypted = keystore.save_keystore(ks_data["wallets"], password)
    let ks_path = config["validator"]["keystore_path"]
    let save_result = ffi_io.write_file(ks_path, encrypted)
    return save_result

# ============================================================
# WALLET KEYSTORE
# ============================================================

proc load_wallet_keystore(config):
    if not config["wallet"]["name"]:
        return [true, nil]

    let ks_path = config["wallet"]["keystore_path"]
    let password = config["wallet"]["password"]

    if not ffi_io.file_exists(ks_path):
        return [false, "wallet keystore not found: " + ks_path]

    let result = ffi_io.load_json(ks_path)
    if not result[0]:
        return result

    # Decrypt keystore
    import orbit.wallet.keystore as keystore
    let decrypted = keystore.load_keystore(result[1], password)
    return [true, decrypted]

proc create_wallet_keystore(config):
    import orbit.wallet.keystore as keystore
    import orbit.wallet.account as account

    let kp = account.generate_keypair(config["wallet"]["seed"])
    let ks_data = {"wallets": [keystore.create_wallet_entry(config["wallet"]["name"], config["wallet"]["seed"])]}
    let password = config["wallet"]["password"]

    let encrypted = keystore.save_keystore(ks_data["wallets"], password)
    let ks_path = config["wallet"]["keystore_path"]
    let save_result = ffi_io.write_file(ks_path, encrypted)
    return save_result