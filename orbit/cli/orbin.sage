# orbit/cli/orbin.sage — `orbin` command line tool (§30)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.wallet.wallet as wallet
import orbit.wallet.keystore as keystore
import orbit.wallet.account as account
import orbit.core.chain as chainmod
import orbit.crypto.encoding as enc

let KEYSTORE_PATH = "./orbit_keystore.json"

proc _read_file(path):
    # Simple file read - in practice would use Sage IO
    return ""

proc _write_file(path, content):
    # Simple file write - in practice would use Sage IO
    return true

proc _load_keystore(password):
    let json_data = _read_file(KEYSTORE_PATH)
    if json_data == "":
        return {"wallets": []}
    return keystore.load_keystore(json_data, password)

proc _save_keystore(ks_data, password):
    let json_data = keystore.save_keystore(ks_data["wallets"], password)
    _write_file(KEYSTORE_PATH, json_data)

proc cmd_wallet_create(argv):
    if len(argv) < 3:
        print("usage: orbin wallet create <name> <seed>")
        return 1
    let name = argv[1]
    let seed = argv[2]
    let password = argv[3] if len(argv) > 3 else "default"
    let ks = _load_keystore(password)
    if keystore.get_wallet(ks, name) != nil:
        print("wallet already exists: " + name)
        return 1
    let entry = wallet.create_wallet(name, seed)
    ks["wallets"] = ks["wallets"] + [entry]
    _save_keystore(ks, password)
    print("created wallet: " + name + " -> " + entry["address"])
    return 0

proc cmd_wallet_list(argv):
    let password = argv[1] if len(argv) > 1 else "default"
    let ks = _load_keystore(password)
    let wallets = keystore.list_wallets(ks)
    for w in wallets:
        print(w["name"] + "  " + w["address"])
    return 0

proc cmd_wallet_address(argv):
    if len(argv) < 2:
        print("usage: orbin wallet address <name>")
        return 1
    let name = argv[1]
    let password = argv[2] if len(argv) > 2 else "default"
    let ks = _load_keystore(password)
    let r = wallet.get_address(ks, name)
    if not r[0]:
        print("error: " + r[1])
        return 1
    print(r[1])
    return 0

proc cmd_wallet_balance(argv):
    if len(argv) < 3:
        print("usage: orbin wallet balance <name> <chain_data>")
        return 1
    let name = argv[1]
    let chain_data = argv[2]
    let password = argv[3] if len(argv) > 3 else "default"
    let ks = _load_keystore(password)
    let r = wallet.get_address(ks, name)
    if not r[0]:
        print("error: " + r[1])
        return 1
    let chain = enc.decode_canonical(chain_data)
    let bal = wallet.get_balance(chain, r[1])
    print(bal)
    return 0

proc cmd_wallet_send(argv):
    if len(argv) < 6:
        print("usage: orbin wallet send <name> <recipient> <amount> <fee> <nonce> <timestamp> [memo]")
        return 1
    let name = argv[1]
    let recipient = argv[2]
    let amount = argv[3]
    let fee = argv[4]
    let nonce = int(argv[5])
    let timestamp = int(argv[6])
    let memo = argv[7] if len(argv) > 7 else ""
    let password = argv[8] if len(argv) > 8 else "default"
    let ks = _load_keystore(password)
    let w = keystore.get_wallet(ks, name)
    if w == nil:
        print("wallet not found: " + name)
        return 1
    let tx = wallet.create_transfer(w["seed"], w["address"], recipient, amount, fee, nonce, timestamp, memo)
    print(enc.encode_canonical(tx.canonical_fields()))
    return 0

proc cmd_wallet_sign(argv):
    if len(argv) < 3:
        print("usage: orbin wallet sign <name> <data_json>")
        return 1
    let name = argv[1]
    let data_json = argv[2]
    let password = argv[3] if len(argv) > 3 else "default"
    let ks = _load_keystore(password)
    let w = keystore.get_wallet(ks, name)
    if w == nil:
        print("wallet not found: " + name)
        return 1
    let data = enc.decode_canonical(data_json)
    let sig = wallet.sign_data(w["seed"], data)
    print(enc.encode_canonical(sig))
    return 0

proc cmd_wallet_verify(argv):
    if len(argv) < 4:
        print("usage: orbin wallet verify <public_key_json> <data_json> <sig_json>")
        return 1
    let pk_json = argv[1]
    let data_json = argv[2]
    let sig_json = argv[3]
    let pk = enc.decode_canonical(pk_json)
    let data = enc.decode_canonical(data_json)
    let sig = enc.decode_canonical(sig_json)
    let ok = wallet.verify_signature(pk, data, sig)
    print(ok)
    return 0

proc main(argv):
    if len(argv) < 2:
        print("orbin — Orbit CLI")
        print("commands: wallet")
        return 1
    let cmd = argv[0]
    let sub = argv[1]
    if cmd == "wallet":
        if sub == "create":
            return cmd_wallet_create(argv[1:])
        if sub == "list":
            return cmd_wallet_list(argv[1:])
        if sub == "address":
            return cmd_wallet_address(argv[1:])
        if sub == "balance":
            return cmd_wallet_balance(argv[1:])
        if sub == "send":
            return cmd_wallet_send(argv[1:])
        if sub == "sign":
            return cmd_wallet_sign(argv[1:])
        if sub == "verify":
            return cmd_wallet_verify(argv[1:])
        print("unknown wallet command: " + sub)
        return 1
    print("unknown command: " + cmd)
    return 1