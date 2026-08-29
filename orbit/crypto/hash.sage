# orbit/crypto/hash.sage — narrow hash interface (§24)
# Orbit Blockchain | Protocol v1 | Status: implemented

import crypto.hash

# Raw SHA-256 (returns 32-byte array)
proc sha256(data):
    return crypto.hash.sha256(data)

# SHA-256 hex string (64 chars)
proc sha256_hex(data):
    let bytes = crypto.hash.sha256(data)
    let hex_chars = "0123456789abcdef"
    let result = ""
    for b in bytes:
        let hi = b / 16
        let lo = b % 16
        result = result + hex_chars[hi] + hex_chars[lo]
    return result
