# orbit/wallet/account.sage — keypairs and orb-prefixed addresses
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet crypto)
#
# Address format (v1):  "orb" + first 40 hex chars of
#                       sha256(canonical(public_key))      -> total length 43.
#
# Keys are Lamport one-time signatures derived deterministically from a seed
# (pure SHA-256, publicly verifiable). DEVNET scheme: one keypair MUST sign
# one transaction; asymmetric ed25519 replaces this before testnet (plan §24).

from crypto.hash import sha256_hex
import orbit.crypto.encoding as enc

let ADDRESS_PREFIX = "orb:"
let ADDRESS_HEX_LEN = 40
let ADDRESS_LEN = 44

proc is_valid_address(a):
    if a == nil or type(a) != "string":
        return false
    if len(a) != ADDRESS_LEN:
        return false
    if slice(a, 0, 4) != ADDRESS_PREFIX:
        return false
    var i = 4
    while i < ADDRESS_LEN:
        let c = a[i]
        let is_digit = c >= "0" and c <= "9"
        let is_hexaf = c >= "a" and c <= "f"
        if not is_digit and not is_hexaf:
            return false
        i = i + 1
    return true

proc _master_seed(seed):
    return sha256_hex("orbit-key-v1:" + seed)

proc _preimage(seed, i, j):
    return sha256_hex(_master_seed(seed) + ":" + str(i) + ":" + str(j))

# 32x2 Lamport public key, canonicalized as an array of 64 hex hashes
proc derive_public_key(seed):
    let pk = []
    var i = 0
    while i < 32:
        push(pk, sha256_hex(_preimage(seed, i, 0)))
        push(pk, sha256_hex(_preimage(seed, i, 1)))
        i = i + 1
    return pk

proc derive_address(seed):
    let pk = derive_public_key(seed)
    return ADDRESS_PREFIX + slice(sha256_hex(enc.encode_canonical(pk)), 0, ADDRESS_HEX_LEN)

proc derive_address_from_public_key(public_key):
    return ADDRESS_PREFIX + slice(sha256_hex(enc.encode_canonical(public_key)), 0, ADDRESS_HEX_LEN)

proc generate_keypair(seed):
    if seed == nil or len(seed) < 8:
        raise "keypair seed too short (>= 8 chars required)"
    # Convention: EVERY public function takes the RAW seed. The master seed
    # is derived exactly once, inside _preimage/_master_seed.
    return {
        "seed": seed,
        "public_key": derive_public_key(seed),
        "address": derive_address(seed),
    }
