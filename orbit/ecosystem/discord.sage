# orbit/ecosystem/discord.sage — Discord bot client (§34)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.api.http as httpmod
import orbit.api.explorer as explore
import orbit.wallet.wallet as wallet
import orbit.wallet.keystore as keystore
import orbit.wallet.account as account
import orbit.crypto.encoding as enc

let BOT_PREFIX = "/orbit"

proc _starts_with(s, prefix):
    if len(s) < len(prefix):
        return false
    var i = 0
    while i < len(prefix):
        if s[i] != prefix[i]:
            return false
        i = i + 1
    return true

proc _split_by_space(s):
    let parts = []
    let current = ""
    var i = 0
    while i < len(s):
        if s[i] == " ":
            if len(current) > 0:
                push(parts, current)
                current = ""
        else:
            current = current + s[i]
        i = i + 1
    if len(current) > 0:
        push(parts, current)
    return parts

class DiscordBot:
    proc init(self, chain, keystore_path = "./orbit_keystore.json"):
        self.chain = chain
        self.keystore_path = keystore_path
        self.server = httpmod.start_server(chain, 8333)
        self.keystore_password = "default"
        self.keystore_data = {"wallets": []}

    proc _save_keystore(self):
        let saved = keystore.save_keystore(self.keystore_data["wallets"], self.keystore_password)

    # Wallet commands
    proc cmd_wallet_create(self, args):
        if len(args) < 2:
            return "Usage: /orbit wallet create <name> <seed>"
        let name = args[0]
        let seed = args[1]
        let entry = wallet.create_wallet(name, seed)
        self.keystore_data["wallets"] = self.keystore_data["wallets"] + [entry]
        self._save_keystore()
        return "Created wallet: " + name + " -> " + entry["address"]

    proc cmd_wallet_list(self, args):
        let wallets = keystore.list_wallets(self.keystore_data)
        if len(wallets) == 0:
            return "No wallets found"
        let out = "Wallets:\n"
        for w in wallets:
            out = out + "  " + w["name"] + "  " + w["address"] + "\n"
        return out

    proc cmd_wallet_balance(self, args):
        if len(args) < 1:
            return "Usage: /orbit wallet balance <name>"
        let name = args[0]
        let r = wallet.get_address(self.keystore_data, name)
        if not r[0]:
            return "Wallet not found: " + name
        let bal = wallet.get_balance(self.chain, r[1])
        return "Balance: " + bal + " base units (" + str(int(bal) / 100000000) + " ORBIT)"

    proc cmd_wallet_send(self, args):
        if len(args) < 6:
            return "Usage: /orbit wallet send <name> <recipient> <amount> <fee> <nonce> <timestamp> [memo]"
        let name = args[0]
        let recipient = args[1]
        let amount = args[2]
        let fee = args[3]
        let nonce = int(args[4])
        let timestamp = int(args[5])
        let memo = ""
        if len(args) > 6:
            memo = args[6]
        let w = keystore.get_wallet(self.keystore_data, name)
        if w == nil:
            return "Wallet not found: " + name
        import orbit.core.transaction as txmod
        let tx = wallet.create_transfer(w["seed"], w["address"], recipient, amount, fee, nonce, timestamp, memo)
        return "Transaction created (unsigned): " + enc.encode_canonical(txmod.canonical_fields(tx))

    # Chain commands
    proc cmd_chain_height(self, args):
        return "Block height: " + str(self.chain.height())

    proc cmd_chain_block(self, args):
        if len(args) < 1:
            return "Usage: /orbit chain block <height|hash>"
        let h = args[0]
        if len(h) == 64:
            let r = explore.get_block_by_hash(self.chain, h)
            if not r[0]:
                return "Block not found"
            return "Block: " + enc.encode_canonical(r[1])
        else:
            let r = explore.get_block_by_height(self.chain, int(h))
            if not r[0]:
                return "Block not found"
            return "Block: " + enc.encode_canonical(r[1])

    proc cmd_chain_tx(self, args):
        if len(args) < 1:
            return "Usage: /orbit chain tx <txid>"
        let r = explore.get_tx_by_id(self.chain, args[0])
        if not r[0]:
            return "Transaction not found"
        return "Transaction: " + enc.encode_canonical(r[1])

    proc cmd_chain_state(self, args):
        let r = explore.get_network_health(self.chain)
        if not r[0]:
            return "Error"
        return "Height: " + str(r[1]["height"]) + ", Finalized: " + str(r[1]["finalized_height"]) + ", Validators: " + str(r[1]["validator_count"]) + ", Pool: " + r[1]["pool_remaining"]

    # Mining commands
    proc cmd_mining_rate(self, args):
        let r = explore.get_mining_stats(self.chain)
        if not r[0]:
            return "Error"
        return "Rate: " + str(r[1]["current_rate"]) + " base units/sec, Pool: " + r[1]["pool_remaining"] + " (" + str(r[1]["pool_exhausted_pct"]) + "% exhausted)"

    # Validator commands
    proc cmd_validator_status(self, args):
        let r = explore.list_validators(self.chain)
        if not r[0]:
            return "No validators"
        let out = "Validators:\n"
        for v in r[1]["validators"]:
            out = out + "  " + v["address"] + "  trust=" + str(v["trust_score"]) + "  uptime=" + str(v["uptime_score"]) + "  status=" + v["status"] + "\n"
        return out

    # Main command router
    proc handle_command(self, message):
        if not _starts_with(message, BOT_PREFIX):
            return nil
        let parts = _split_by_space(message)
        let cmd = ""
        if len(parts) > 1:
            cmd = parts[1]
        let args = []
        if len(parts) > 2:
            args = parts[2:]

        if cmd == "wallet":
            let sub = ""
            if len(args) > 0:
                sub = args[0]
            if sub == "create":
                return self.cmd_wallet_create(args[1:])
            if sub == "list":
                return self.cmd_wallet_list(args[1:])
            if sub == "balance":
                return self.cmd_wallet_balance(args[1:])
            if sub == "send":
                return self.cmd_wallet_send(args[1:])
            return "Unknown wallet command: " + sub

        if cmd == "chain":
            let sub = ""
            if len(args) > 0:
                sub = args[0]
            if sub == "height":
                return self.cmd_chain_height(args[1:])
            if sub == "block":
                return self.cmd_chain_block(args[1:])
            if sub == "tx":
                return self.cmd_chain_tx(args[1:])
            if sub == "state":
                return self.cmd_chain_state(args[1:])
            return "Unknown chain command: " + sub

        if cmd == "mining":
            let sub = ""
            if len(args) > 0:
                sub = args[0]
            if sub == "rate":
                return self.cmd_mining_rate(args[1:])
            return "Unknown mining command: " + sub

        if cmd == "validator":
            let sub = ""
            if len(args) > 0:
                sub = args[0]
            if sub == "status":
                return self.cmd_validator_status(args[1:])
            return "Unknown validator command: " + sub

        if cmd == "help":
            return self.help_text()

        return "Unknown command. Use /orbit help"

    proc help_text(self):
        return "Orbit Discord Bot Commands:\n/orbit wallet create <name> <seed>    Create new wallet\n/orbit wallet list                    List wallets\n/orbit wallet balance <name>          Check balance\n/orbit wallet send <name> <to> <amt> <fee> <nonce> <ts> [memo]  Send ORBIT\n/orbit chain height                   Current block height\n/orbit chain block <height|hash>      Block details\n/orbit chain tx <txid>                Transaction details\n/orbit chain state                    Network state\n/orbit mining rate                    Current mining rate\n/orbit validator status               Validator list\n/orbit help                           This help"

proc start_bot(chain):
    let bot = DiscordBot(chain)
    print("Orbit Discord bot initialized")
    print("Prefix: " + BOT_PREFIX)
    return bot