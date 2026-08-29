# orbit/ffi/io.sage — file I/O with FFI fallback
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.ffi.bindings as ffi

# Internal state
let _use_ffi = ffi.ffi_available()

# ============================================================
# PUBLIC API
# ============================================================

# Read entire file as string
# Returns: [ok, content_or_error]
proc read_file(path):
    if _use_ffi:
        return ffi.ffi_read_file(path)
    else:
        return [false, "file I/O not available (no FFI)"]

# Write file (create or overwrite)
# Returns: [ok, error_or_nil]
proc write_file(path, content):
    if _use_ffi:
        return ffi.ffi_write_file(path, content)
    else:
        return [false, "file I/O not available (no FFI)"]

# Append to file
proc append_file(path, content):
    if _use_ffi:
        return ffi.ffi_append_file(path, content)
    else:
        return [false, "file I/O not available (no FFI)"]

# Check if file exists
proc file_exists(path):
    if _use_ffi:
        return ffi.ffi_file_exists(path)[1]
    else:
        return false

# Create directory recursively
proc mkdir_p(path):
    if _use_ffi:
        return ffi.ffi_mkdir_p(path)
    else:
        return [false, "mkdir not available (no FFI)"]

# List directory
proc list_dir(path):
    if _use_ffi:
        return ffi.ffi_list_dir(path)
    else:
        return [false, "list_dir not available (no FFI)"]

# Remove file
proc remove_file(path):
    if _use_ffi:
        return ffi.ffi_remove_file(path)
    else:
        return [false, "remove not available (no FFI)"]

# Get file size
proc file_size(path):
    if _use_ffi:
        return ffi.ffi_file_size(path)
    else:
        return [false, "file_size not available (no FFI)"]

# Get file modification time
proc file_mtime(path):
    if _use_ffi:
        return ffi.ffi_file_mtime(path)
    else:
        return [false, "file_mtime not available (no FFI)"]

# ============================================================
# JSON HELPERS
# ============================================================

proc save_json(data, path):
    import orbit.crypto.encoding as enc
    let content = enc.encode_canonical(data)
    return write_file(path, content)

proc load_json(path):
    let result = read_file(path)
    if not result[0]:
        return result
    import orbit.crypto.encoding as enc
    let data = enc.decode_canonical(result[1])
    return [true, data]

# ============================================================
# CONFIG HELPERS
# ============================================================

proc save_config(config, path):
    return save_json(config, path)

proc load_config(path):
    return load_json(path)

# ============================================================
# BLOCK/STATE/CHAIN HELPERS
# ============================================================

proc save_block(block, path):
    let data = {"block": block, "saved_at": time_now()}
    return save_json(data, path)

proc load_block(path):
    return load_json(path)

proc save_state(state, path):
    let data = {
        "accounts": state.accounts,
        "contracts": state.contracts,
        "saved_at": time_now(),
    }
    return save_json(data, path)

proc load_state(path):
    let result = load_json(path)
    if not result[0]:
        return result
    import orbit.core.state as statemod
    let state = statemod.WorldState()
    state.accounts = result[1]["accounts"] or {}
    state.contracts = result[1]["contracts"] or {}
    return [true, state]

proc save_chain(chain, path):
    let data = {
        "blocks": chain.blocks,
        "pool_remaining": chain.pool_remaining,
        "finalized_height": chain.finalized_height,
        "certificates": chain.certificates,
        "validators": chain.validators,
        "saved_at": time_now(),
    }
    return save_json(data, path)

proc load_chain(path):
    let result = load_json(path)
    if not result[0]:
        return result
    import orbit.core.chain as chainmod
    let chain = chainmod.Chain("orbit-devnet")  # network_id from config
    chain.blocks = result[1]["blocks"] or []
    chain.pool_remaining = result[1]["pool_remaining"] or "0"
    chain.finalized_height = result[1]["finalized_height"] or 0
    chain.certificates = result[1]["certificates"] or {}
    chain.validators = result[1]["validators"]
    return [true, chain]

# ============================================================
# TIME HELPERS
# ============================================================

proc time_now():
    if _use_ffi:
        return ffi.ffi_time_now()
    else:
        return 0

proc time_now_ms():
    if _use_ffi:
        return ffi.ffi_time_now_ms()
    else:
        return 0

proc sleep_ms(ms):
    if _use_ffi:
        return ffi.ffi_sleep_ms(ms)
    else:
        return [false, "sleep not available (no FFI)"]