# orbit/ecosystem/web_wallet.sage — Web wallet client (Phase 9)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.wallet.wallet as wallet
import orbit.wallet.keystore as keystore
import orbit.wallet.account as account
import orbit.api.explorer as explore
import orbit.crypto.encoding as enc
import orbit.core.transaction as txmod

class WebWallet:
    proc init(self, chain):
        self.chain = chain
        self.current_wallet = nil
        self.keystore_password = "default"

    # Wallet management
    proc create_wallet(self, name, seed):
        let entry = wallet.create_wallet(name, seed)
        return {"success": true, "wallet": entry}

    proc import_wallet(self, name, seed):
        let entry = wallet.import_wallet(name, seed)
        return {"success": true, "wallet": entry}

    proc load_wallet(self, keystore_json, name, password):
        let ks_data = keystore.load_keystore(keystore_json, password)
        let w = keystore.get_wallet(ks_data, name)
        if w == nil:
            return {"success": false, "error": "Wallet not found"}
        self.current_wallet = w
        return {"success": true, "address": w["address"], "name": w["name"]}

    proc get_wallet_list(self, keystore_json, password):
        let ks_data = keystore.load_keystore(keystore_json, password)
        let wallets = keystore.list_wallets(ks_data)
        return {"wallets": wallets}

    proc save_keystore(self, wallets):
        return keystore.save_keystore(wallets, self.keystore_password)

    # Balance & state
    proc get_balance(self, address):
        return wallet.get_balance(self.chain, address)

    proc get_nonce(self, address):
        return wallet.get_nonce(self.chain, address)

    proc get_address_state(self, address):
        let r = explore.get_address(self.chain, address)
        if not r[0]:
            return {"error": "Address not found"}
        return r[1]

    proc get_address_txs(self, address, limit = 20):
        let r = explore.get_address_txs(self.chain, address, limit)
        if not r[0]:
            return {"error": "Address not found"}
        return r[1]

    # Transaction creation
    proc create_transfer(self, seed, sender, recipient, amount, fee, nonce, timestamp, memo = ""):
        let tx = wallet.create_transfer(seed, sender, recipient, amount, fee, nonce, timestamp, memo)
        return {"tx_id": tx.tx_id, "canonical": enc.encode_canonical(txmod.canonical_fields(tx))}

    proc create_lock(self, seed, sender, amount, fee, nonce, timestamp, lock_duration, claim_height, lockup_id):
        import orbit.core.transaction as txmod
        let tx = txmod.Transaction(txmod.KIND_LOCK, sender, sender, amount, fee, nonce, timestamp)
        tx.lock_duration = lock_duration
        tx.claim_height = claim_height
        tx.lockup_id = lockup_id
        txmod.sign_with(tx, seed)
        return {"tx_id": tx.tx_id, "canonical": enc.encode_canonical(txmod.canonical_fields(tx))}

    proc create_unlock(self, seed, sender, fee, nonce, timestamp, lockup_id):
        import orbit.core.transaction as txmod
        let tx = txmod.Transaction(txmod.KIND_UNLOCK, sender, "", "0", fee, nonce, timestamp)
        tx.lockup_id = lockup_id
        txmod.sign_with(tx, seed)
        return {"tx_id": tx.tx_id, "canonical": enc.encode_canonical(txmod.canonical_fields(tx))}

    proc create_claim(self, seed, sender, fee, nonce, timestamp, lockup_id):
        import orbit.core.transaction as txmod
        let tx = txmod.Transaction(txmod.KIND_CLAIM, sender, "", "0", fee, nonce, timestamp)
        tx.lockup_id = lockup_id
        txmod.sign_with(tx, seed)
        return {"tx_id": tx.tx_id, "canonical": enc.encode_canonical(txmod.canonical_fields(tx))}

    # Signing/verification
    proc sign_data(self, seed, data):
        let sig = wallet.sign_data(seed, data)
        return {"signature": enc.encode_canonical(sig)}

    proc verify_signature(self, pubkey_json, data_json, sig_json):
        let pk = enc.decode_canonical(pubkey_json)
        let data = enc.decode_canonical(data_json)
        let sig = enc.decode_canonical(sig_json)
        let ok = wallet.verify_signature(pk, data, sig)
        return {"valid": ok}

    # Network info
    proc get_network_status(self):
        let r = explore.get_network_health(self.chain)
        if not r[0]:
            return {"error": "Failed to get network health"}
        return r[1]

    proc get_mining_stats(self):
        let r = explore.get_mining_stats(self.chain)
        if not r[0]:
            return {"error": "Failed to get mining stats"}
        return r[1]

    proc get_validators(self):
        let r = explore.list_validators(self.chain)
        if not r[0]:
            return {"error": "Failed to get validators"}
        return r[1]

    proc get_latest_blocks(self, page = 0, limit = 20):
        let r = explore.list_blocks(self.chain, page, limit)
        if not r[0]:
            return {"error": "Failed to get blocks"}
        return r[1]

    proc get_latest_txs(self, page = 0, limit = 50):
        let r = explore.list_txs(self.chain, page, limit)
        if not r[0]:
            return {"error": "Failed to get transactions"}
        return r[1]

    # Generate keypair
    proc generate_keypair(self, seed):
        let kp = account.generate_keypair(seed)
        return {
            "seed": kp["seed"],
            "address": kp["address"],
            "public_key": enc.encode_canonical(kp["public_key"]),
        }

proc create_web_wallet(chain):
    return WebWallet(chain)