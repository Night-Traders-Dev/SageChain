# orbit/wallet/wallet.sage — wallet operations (§23)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.wallet.account as account
import orbit.wallet.keystore as keystore
import orbit.crypto.signatures as sig
import orbit.crypto.encoding as enc

# API: create import export lock unlock address balance send sign verify

proc create_wallet(name, seed):
    return keystore.create_wallet_entry(name, seed)

proc import_wallet(name, seed):
    return keystore.create_wallet_entry(name, seed)

proc export_wallet(keystore_data, name, password):
    let wallet = keystore.get_wallet(keystore_data, name)
    if wallet == nil:
        return [false, "wallet not found"]
    return [true, wallet["seed"]]

proc get_address(keystore_data, name):
    let wallet = keystore.get_wallet(keystore_data, name)
    if wallet == nil:
        return [false, "wallet not found"]
    return [true, wallet["address"]]

proc get_public_key(keystore_data, name):
    let wallet = keystore.get_wallet(keystore_data, name)
    if wallet == nil:
        return [false, "wallet not found"]
    return [true, wallet["public_key"]]

proc sign_data(seed, data):
    let signature = sig.sign(seed, enc.encode_canonical(data))
    return signature

proc verify_signature(public_key, data, signature):
    return sig.verify(public_key, enc.encode_canonical(data), signature)

proc create_transfer(seed, sender_addr, recipient, amount, fee, nonce, timestamp, memo = ""):
    import orbit.core.transaction as txmod
    let t = txmod.Transaction(
        txmod.KIND_TRANSFER,
        sender_addr,
        recipient,
        str(amount),
        str(fee),
        nonce,
        timestamp
    )
    t.memo = memo
    txmod.sign_with(t, seed)
    return t

proc get_balance(chain, address):
    let acc = chain.state.accounts[address]
    if acc == nil:
        return "0"
    return acc["balance"]

proc get_nonce(chain, address):
    let acc = chain.state.accounts[address]
    if acc == nil:
        return 0
    return acc["nonce"]