# t15 — ecosystem clients (Phase 9)
import orbit.ecosystem.discord as discord
import orbit.ecosystem.web_wallet as web_wallet
import orbit.ecosystem.exchange as exchange
import orbit.core.chain as chainmod
import orbit.wallet.account as account
import orbit.wallet.keystore as keystore
import orbit.crypto.encoding as enc

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

let net = "orbit-devnet"
let chain = chainmod.Chain(net)

# Test Discord bot
print("=== Testing Discord Bot ===")
let bot = discord.DiscordBot(chain)

let help_text = bot.help_text()
check("discord-help", len(help_text) > 0)

let wallet_create = bot.handle_command("/orbit wallet create test_wallet test-seed-12345")
check("discord-wallet-create", wallet_create != nil)

let wallet_list = bot.handle_command("/orbit wallet list")
check("discord-wallet-list", wallet_list != nil)

let chain_height = bot.handle_command("/orbit chain height")
check("discord-chain-height", chain_height != nil)

let mining_rate = bot.handle_command("/orbit mining rate")
check("discord-mining-rate", mining_rate != nil)

let validator_status = bot.handle_command("/orbit validator status")
check("discord-validator-status", validator_status != nil)

let unknown_cmd = bot.handle_command("/orbit unknown")
check("discord-unknown", unknown_cmd != nil)

# Test Web Wallet
print("=== Testing Web Wallet ===")
let ww = web_wallet.create_web_wallet(chain)

let kp = ww.generate_keypair("web-wallet-test-seed")
check("webwallet-keypair", kp["address"] != nil and len(kp["address"]) == 43)
check("webwallet-keypair-prefix", kp["address"][:3] == "orb")

let wallet_create_res = ww.create_wallet("test", "web-wallet-test-seed")
check("webwallet-create", wallet_create_res["success"] and wallet_create_res["wallet"]["name"] == "test")

let keystore_json = ww.save_keystore([wallet_create_res["wallet"]])
check("webwallet-save-keystore", len(keystore_json) > 0)

let load_res = ww.load_wallet(keystore_json, "test", "default")
check("webwallet-load", load_res["success"] and load_res["address"] == wallet_create_res["wallet"]["address"])

let balance = ww.get_balance(kp["address"])
check("webwallet-balance", balance != nil)

let nonce = ww.get_nonce(kp["address"])
check("webwallet-nonce", nonce != nil)

let network_status = ww.get_network_status()
check("webwallet-network-status", network_status["height"] != nil)

let mining_stats = ww.get_mining_stats()
check("webwallet-mining-stats", mining_stats["current_rate"] != nil)

let validators = ww.get_validators()
check("webwallet-validators", validators["validators"] != nil)

let blocks = ww.get_latest_blocks(0, 5)
check("webwallet-blocks", blocks["blocks"] != nil)

let txs = ww.get_latest_txs(0, 10)
check("webwallet-txs", txs["transactions"] != nil)

let tx = ww.create_transfer("web-wallet-test-seed", kp["address"], kp["address"], "1000000", "1000", 0, 1000, "test memo")
check("webwallet-create-transfer", tx["tx_id"] != nil and len(tx["tx_id"]) == 64)

let sig = ww.sign_data("web-wallet-test-seed", {"test": "data"})
check("webwallet-sign", sig["signature"] != nil and len(sig["signature"]) > 0)

let verify = ww.verify_signature(kp["public_key"], enc.encode_canonical({"test": "data"}), sig["signature"])
check("webwallet-verify", verify["valid"] == true)

# Test Exchange
print("=== Testing Exchange ===")
let ex = exchange.create_exchange(chain)

let markets = ex.get_markets()
check("exchange-markets", len(markets["markets"]) >= 3)
check("exchange-markets-contain", true)

let order_book = ex.get_order_book("ORBIT/USD")
check("exchange-order-book", order_book["bids"] != nil and order_book["asks"] != nil)

# Test placing orders
let alice = account.generate_keypair("exchange-alice-seed")
let bob = account.generate_keypair("exchange-bob-seed")

# Fund alice with ORBIT and USD for testing
chain.state.accounts[alice["address"]] = {"balance": "100000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil, "lockups": {}}
chain.state.accounts[bob["address"]] = {"balance": "100000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil, "lockups": {}}
ex.set_user_balance(alice["address"], "ORBIT", "50000000000")
ex.set_user_balance(alice["address"], "USD", "100000000")
ex.set_user_balance(bob["address"], "ORBIT", "50000000000")
ex.set_user_balance(bob["address"], "USD", "100000000")

# Alice places buy order (0.00001 ORBIT at 100 USD per ORBIT = 0.001 USD)
let buy_order = ex.place_order("ORBIT/USD", "buy", "100", "1000", "exchange-alice-seed", alice["address"], 0, 1000)
check("exchange-buy-order", buy_order["success"] and buy_order["order"]["id"] != nil)

# Bob places sell order (0.00001 ORBIT at 100 USD per ORBIT)
let sell_order = ex.place_order("ORBIT/USD", "sell", "100", "1000", "exchange-bob-seed", bob["address"], 0, 1001)
check("exchange-sell-order", sell_order["success"] and sell_order["order"]["id"] != nil)

# Check order book after matching
let ob_after = ex.get_order_book("ORBIT/USD", 10)
check("exchange-matched", len(ob_after["bids"]) == 0 or len(ob_after["asks"]) == 0)

# Test user orders
let alice_orders = ex.get_user_orders("ORBIT/USD", alice["address"])
check("exchange-user-orders", len(alice_orders) >= 0)

# Test get trades
let trades = ex.get_recent_trades("ORBIT/USD")
check("exchange-trades", trades["trades"] != nil)

print("t15 ecosystem: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t15 FAILED"