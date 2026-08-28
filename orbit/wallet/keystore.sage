# orbit/wallet/keystore.sage — encrypted local key storage
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.crypto.encoding as enc
from crypto.hash import sha256_hex

let KEYSTORE_VERSION = 1
let KEYSTORE_FILE = "orbit_keystore.json"

let HEX_CHARS = "0123456789abcdef"

proc _hex_char(val):
    if val == 0: return "0"
    if val == 1: return "1"
    if val == 2: return "2"
    if val == 3: return "3"
    if val == 4: return "4"
    if val == 5: return "5"
    if val == 6: return "6"
    if val == 7: return "7"
    if val == 8: return "8"
    if val == 9: return "9"
    if val == 10: return "a"
    if val == 11: return "b"
    if val == 12: return "c"
    if val == 13: return "d"
    if val == 14: return "e"
    return "f"

proc _from_hex_char(c):
    if c == "0": return 0
    if c == "1": return 1
    if c == "2": return 2
    if c == "3": return 3
    if c == "4": return 4
    if c == "5": return 5
    if c == "6": return 6
    if c == "7": return 7
    if c == "8": return 8
    if c == "9": return 9
    if c == "a": return 10
    if c == "b": return 11
    if c == "c": return 12
    if c == "d": return 13
    if c == "e": return 14
    if c == "f": return 15
    return 0

proc _to_hex(byte):
    let hi = int(byte / 16)
    let lo = byte % 16
    return _hex_char(hi) + _hex_char(lo)

proc _from_hex(two_chars):
    let hi = _from_hex_char(two_chars[0])
    let lo = _from_hex_char(two_chars[1])
    return hi * 16 + lo

proc _derive_encryption_key(password):
    return sha256_hex("orbit-keystore-v1:" + password)

proc _xor_encrypt_hex(data, key):
    let out = ""
    var i = 0
    while i < len(data):
        let k = ord(key[i % len(key)])
        let d = ord(data[i])
        let x = k ^ d
        out = out + _to_hex(x)
        i = i + 1
    return out

proc _xor_decrypt_hex(hex_data, key):
    let out = ""
    var i = 0
    while i < len(hex_data):
        let byte_str = slice(hex_data, i, i + 2)
        let byte_val = _from_hex(byte_str)
        let k = ord(key[int(i / 2) % len(key)])
        let x = byte_val ^ k
        out = out + chr(x)
        i = i + 2
    return out

proc _encrypt_json(obj, password):
    let key = _derive_encryption_key(password)
    let plaintext = enc.encode_canonical(obj)
    let ciphertext = _xor_encrypt_hex(plaintext, key)
    return {
        "version": KEYSTORE_VERSION,
        "ciphertext": ciphertext,
        "checksum": sha256_hex(plaintext),
    }

proc _decrypt_json(encrypted, password):
    let key = _derive_encryption_key(password)
    let plaintext = _xor_decrypt_hex(encrypted["ciphertext"], key)
    if sha256_hex(plaintext) != encrypted["checksum"]:
        raise "keystore: invalid password or corrupted data"
    return enc.decode_canonical(plaintext)

proc save_keystore(wallets, password):
    let data = {
        "wallets": wallets,
        "created": enc.encode_canonical({}),
    }
    let encrypted = _encrypt_json(data, password)
    return enc.encode_canonical(encrypted)

proc load_keystore(json_data, password):
    let encrypted = enc.decode_canonical(json_data)
    if encrypted["version"] != KEYSTORE_VERSION:
        raise "keystore: unsupported version"
    return _decrypt_json(encrypted, password)

proc create_wallet_entry(name, seed):
    import orbit.wallet.account as account
    let kp = account.generate_keypair(seed)
    return {
        "name": name,
        "address": kp["address"],
        "public_key": kp["public_key"],
        "seed": seed,
        "created_at": 0,
    }

proc list_wallets(keystore_data):
    let out = []
    for w in keystore_data["wallets"]:
        push(out, {"name": w["name"], "address": w["address"]})
    return out

proc get_wallet(keystore_data, name):
    for w in keystore_data["wallets"]:
        if w["name"] == name:
            return w
    return nil

proc delete_wallet(keystore_data, name):
    var new_wallets = []
    var found = false
    for w in keystore_data["wallets"]:
        if w["name"] == name:
            found = true
        else:
            push(new_wallets, w)
    if not found:
        return [false, "wallet not found"]
    keystore_data["wallets"] = new_wallets
    return [true, nil]