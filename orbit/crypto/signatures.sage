# orbit/crypto/signatures.sage — Lamport one-time signatures over SHA-256
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet scheme)
#
# sign(seed, data): hash data -> 256 bits; reveal preimage per bit.
# verify(pk, data, sig): each revealed preimage must hash to its pk leaf.
# ONE-TIME: never reuse a seed for two signatures (documented devnet scheme;
# replace with ed25519 before testnet — plan §24).

from crypto.hash import sha256_hex
import orbit.wallet.account as acct

proc _bit_at(msg_hash, i):
    # bit i of the 256-bit message, MSB-first per hex nibble
    let ch = ord(msg_hash[int(i / 2)])
    if i % 2 == 0:
        return int(ch / 16) % 2
    return ch % 2

proc sign(seed, data):
    let msg_hash = sha256_hex(data)
    let sig = []
    var i = 0
    while i < 32:
        let j = _bit_at(msg_hash, i)
        # reveal the RAW preimage — verify() hashes it against the pub leaf
        push(sig, acct._preimage(seed, i, j))
        i = i + 1
    return sig

proc verify(public_key, data, signature):
    if type(public_key) != "array" or len(public_key) != 64:
        return false
    if type(signature) != "array" or len(signature) != 32:
        return false
    let msg_hash = sha256_hex(data)
    var i = 0
    while i < 32:
        let j = _bit_at(msg_hash, i)
        if sha256_hex(signature[i]) != public_key[i * 2 + j]:
            return false
        i = i + 1
    return true

proc address_for_public_key(public_key):
    return acct.derive_address_from_public_key(public_key)
