# orbit/node/config.sage — configuration system
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.crypto.encoding as enc

# TOML-like config parser (simplified)
proc parse_config(text):
    let lines = text.split("\n")
    let config = {}
    let current_section = ""
    for line in lines:
        line = line.strip()
        if line == "" or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current_section = line[1:-1]
            config[current_section] = {}
        else:
            let eq = line.find("=")
            if eq > 0:
                let key = line[:eq].strip()
                let val = line[eq+1:].strip()
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif val == "true":
                    val = true
                elif val == "false":
                    val = false
                elif val.isdigit():
                    val = int(val)
                if current_section:
                    config[current_section][key] = val
                else:
                    config[key] = val
    return config

proc load_config(path):
    import orbit.storage.json_store as js
    return js.load_json(path)

proc save_config(config, path):
    import orbit.storage.json_store as js
    return js.save_json(config, path)

# Default configuration
proc default_config():
    return {
        "network": {
            "network_id": "orbit-devnet",
            "listen_addr": "0.0.0.0:8333",
            "bootstrap_peers": [],
            "max_peers": 50,
        },
        "mining": {
            "enabled": true,
            "threads": 1,
            "max_block_time": 500,
        },
        "rpc": {
            "enabled": true,
            "listen_addr": "127.0.0.1:8545",
            "cors_origins": ["*"],
        },
        "explorer": {
            "enabled": true,
            "listen_addr": "127.0.0.1:3000",
        },
        "storage": {
            "data_dir": "./data",
            "engine": "json",
        },
        "validator": {
            "enabled": false,
            "keystore_path": "./validator_keystore.json",
            "password": "",
        },
        "logging": {
            "level": "info",
            "format": "json",
            "file": "./logs/orbit.log",
        },
        "metrics": {
            "enabled": true,
            "listen_addr": "127.0.0.1:9090",
        },
    }

# Genesis configuration
proc default_genesis():
    return {
        "network_id": "orbit-devnet",
        "chain_id": 1,
        "timestamp": 0,
        "allocations": {
            "system": "8190000000000000000",
            "lockup_rewards": "10000000000000000",
            "mining": "100000000000000000",
            "community": "300000000000000000",
            "team": "500000000000000000",
            "airdrop": "100000000000000000",
            "foundation": "200000000000000000",
            "partnerships": "100000000000000000",
            "reserve": "500000000000000000",
        },
        "mining_params": {
            "r_base": "8200000",
            "u_target": 10000,
            "s_max": "100000000000000000",
            "b_halflife": 100000,
            "node_boost_max": 100000,
        },
        "validators": [],
    }

proc load_genesis(path):
    import orbit.storage.json_store as js
    return js.load_json(path)

proc save_genesis(genesis, path):
    import orbit.storage.json_store as js
    return js.save_json(genesis, path)