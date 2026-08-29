# orbit/storage/json_store.sage — JSON persistence backend
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.crypto.encoding as enc

proc load_json(path):
    # In a real implementation, this would read from filesystem
    # For now, return empty/default structures
    return {}

proc save_json(data, path):
    # In a real implementation, this would write to filesystem
    return true

# File-based storage (when FFI for file I/O is available)
proc read_file(path):
    # Placeholder - needs FFI
    return ""

proc write_file(path, content):
    # Placeholder - needs FFI
    return true

# Block storage
proc save_block(block, path):
    import orbit.storage.json_store as js
    let data = {
        "block": block,
        "saved_at": 0,  # timestamp
    }
    return js.save_json(data, path)

proc load_block(path):
    import orbit.storage.json_store as js
    let data = js.load_json(path)
    return data["block"]

# State storage
proc save_state(state, path):
    import orbit.storage.json_store as js
    let data = {
        "accounts": state.accounts,
        "contracts": state.contracts,
        "saved_at": 0,
    }
    return js.save_json(data, path)

proc load_state(path):
    import orbit.storage.json_store as js
    let data = js.load_json(path)
    import orbit.core.state as statemod
    let state = statemod.WorldState()
    state.accounts = data["accounts"] or {}
    state.contracts = data["contracts"] or {}
    return state

# Chain storage
proc save_chain(chain, path):
    import orbit.storage.json_store as js
    let data = {
        "blocks": chain.blocks,
        "pool_remaining": chain.pool_remaining,
        "finalized_height": chain.finalized_height,
        "certificates": chain.certificates,
        "validators": chain.validators,
        "saved_at": 0,
    }
    return js.save_json(data, path)

proc load_chain(path):
    import orbit.storage.json_store as js
    import orbit.core.chain as chainmod
    let data = js.load_json(path)
    let chain = chainmod.Chain(data["network_id"])
    chain.blocks = data["blocks"] or []
    chain.pool_remaining = data["pool_remaining"] or 0
    chain.finalized_height = data["finalized_height"] or 0
    chain.certificates = data["certificates"] or {}
    chain.validators = data["validators"]
    return chain

# Keystore storage
proc save_keystore(keystore, path):
    import orbit.storage.json_store as js
    return js.save_json(keystore, path)

proc load_keystore(path):
    import orbit.storage.json_store as js
    return js.load_json(path)

# Config storage
proc save_config(config, path):
    import orbit.storage.json_store as js
    return js.save_json(config, path)

proc load_config(path):
    import orbit.storage.json_store as js
    return js.load_json(path)

# Genesis storage
proc save_genesis(genesis, path):
    import orbit.storage.json_store as js
    return js.save_json(genesis, path)

proc load_genesis(path):
    import orbit.storage.json_store as js
    return js.load_json(path)