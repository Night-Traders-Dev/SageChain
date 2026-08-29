# orbit/storage/json_store.sage — JSON persistence backend
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.crypto.encoding as enc
import orbit.ffi.bindings as ffi_bindings

# Export FFI functions for convenience
let ffi_read_file = ffi_bindings.ffi_read_file
let ffi_write_file = ffi_bindings.ffi_write_file
let ffi_file_exists = ffi_bindings.ffi_file_exists
let ffi_mkdir_p = ffi_bindings.ffi_mkdir_p

# Internal cache for decoded JSON (simple memoization)
let _json_cache = {}

# Parse JSON string to object
# This is a simplified parser - in production would use a proper JSON parser
proc parse_json(text):
    # For now, use the encoding module's decode_canonical which handles a subset
    return enc.decode_canonical(text)

# Convert object to JSON string
proc stringify_json(obj):
    return enc.encode_canonical(obj)

# Read and parse JSON file
proc load_json(path):
    let result = ffi_read_file(path)
    if not result[0]:
        return result
    let content = result[1]
    let parsed = parse_json(content)
    return [true, parsed]

# Write object as JSON file
proc save_json(obj, path):
    let json_str = stringify_json(obj)
    let result = ffi_write_file(path, json_str)
    return result

# Check if file exists
proc file_exists(path):
    let result = ffi_file_exists(path)
    return result[1]

# Create directory
proc mkdir_p(path):
    let result = ffi_mkdir_p(path)
    return result