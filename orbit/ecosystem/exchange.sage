# orbit/ecosystem/exchange.sage — Exchange client (Phase 9)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.wallet.wallet as wallet
import orbit.wallet.keystore as keystore
import orbit.wallet.account as account
import orbit.core.transaction as txmod
import orbit.api.explorer as explore
import orbit.crypto.encoding as enc
import orbit.core.bigint as bi

proc _min(a, b):
    if a < b:
        return a
    return b

proc _split(s, delim):
    let parts = []
    let current = ""
    var i = 0
    while i < len(s):
        if s[i] == delim:
            push(parts, current)
            current = ""
        else:
            current = current + s[i]
        i = i + 1
    push(parts, current)
    return parts

class ExchangeClient:
    proc init(self, chain):
        self.chain = chain
        self.order_book = {}  # market -> {"bids": [], "asks": []}
        self.balances = {}    # user -> {asset -> amount}

    # Market management
    proc create_market(self, base_asset, quote_asset):
        let market = base_asset + "/" + quote_asset
        self.order_book[market] = {"bids": [], "asks": []}
        return {"success": true, "market": market}

    proc get_markets(self):
        let markets = []
        for m in self.order_book:
            push(markets, m)
        return {"markets": markets}

    # Order placement
    proc place_order(self, market, side, price, amount, user_wallet_seed, user_address, nonce, timestamp):
        if not dict_has(self.order_book, market):
            return {"success": false, "error": "Market not found"}

        let parts = _split(market, "/")
        let base = parts[0]
        let quote_asset = parts[1]

        if side == "buy":
            let total_cost = bi.bi_mul(amount, price)
            let fee = "1000"
            let spend = bi.bi_add(total_cost, fee)
            if bi.bi_cmp(spend, self.get_user_balance(user_address, quote_asset)) > 0:
                return {"success": false, "error": "Insufficient " + quote_asset + " balance"}

            let order = {
                "id": self.generate_order_id(),
                "market": market,
                "side": "buy",
                "price": price,
                "amount": amount,
                "filled": "0",
                "user": user_address,
                "timestamp": timestamp,
            }
            push(self.order_book[market]["bids"], order)
            self.match_orders(market)
            return {"success": true, "order": order}

        if side == "sell":
            if bi.bi_cmp(amount, self.get_user_balance(user_address, base)) > 0:
                return {"success": false, "error": "Insufficient " + base + " balance"}

            let order = {
                "id": self.generate_order_id(),
                "market": market,
                "side": "sell",
                "price": price,
                "amount": amount,
                "filled": "0",
                "user": user_address,
                "timestamp": timestamp,
            }
            push(self.order_book[market]["asks"], order)
            self.match_orders(market)
            return {"success": true, "order": order}

        return {"success": false, "error": "Invalid side"}

    proc get_user_balance(self, address, asset):
        if not dict_has(self.balances, address):
            self.balances[address] = {}
        if not dict_has(self.balances[address], asset):
            return "0"
        return self.balances[address][asset]

    proc set_user_balance(self, address, asset, amount):
        if not dict_has(self.balances, address):
            self.balances[address] = {}
        self.balances[address][asset] = amount

    proc generate_order_id(self):
        let id = "ord_" + str(int(1000000 * (self.chain.height() + 1)))
        return id

    # Order matching
    proc match_orders(self, market):
        let ob = self.order_book[market]
        # Sort bids by price descending, asks by price ascending
        ob["bids"] = self.sort_orders(ob["bids"], "desc")
        ob["asks"] = self.sort_orders(ob["asks"], "asc")

        var i = 0
        var j = 0
        while i < len(ob["bids"]) and j < len(ob["asks"]):
            let bid = ob["bids"][i]
            let ask = ob["asks"][j]
            if bi.bi_cmp(bid["price"], ask["price"]) >= 0:
                let trade_price = ask["price"]
                let bid_remaining = bi.bi_sub(bid["amount"], bid["filled"])
                let ask_remaining = bi.bi_sub(ask["amount"], ask["filled"])
                let trade_amount = bid_remaining
                if bi.bi_cmp(ask_remaining, trade_amount) < 0:
                    trade_amount = ask_remaining

                # Execute trade
                self.execute_trade(market, bid, ask, trade_amount, trade_price)

                bid["filled"] = bi.bi_add(bid["filled"], trade_amount)
                ask["filled"] = bi.bi_add(ask["filled"], trade_amount)

                if bi.bi_cmp(bid["filled"], bid["amount"]) >= 0:
                    i = i + 1
                if bi.bi_cmp(ask["filled"], ask["amount"]) >= 0:
                    j = j + 1
            else:
                break

        # Remove filled orders
        let new_bids = []
        for b in ob["bids"]:
            if bi.bi_cmp(b["filled"], b["amount"]) < 0:
                push(new_bids, b)
        ob["bids"] = new_bids

        let new_asks = []
        for a in ob["asks"]:
            if bi.bi_cmp(a["filled"], a["amount"]) < 0:
                push(new_asks, a)
        ob["asks"] = new_asks

    proc execute_trade(self, market, bid, ask, amount, price):
        let parts = _split(market, "/")
        let base = parts[0]
        let quote_asset = parts[1]

        # Update balances
        let bid_quote_bal = self.get_user_balance(bid["user"], quote_asset)
        let bid_base_bal = self.get_user_balance(bid["user"], base)
        let ask_quote_bal = self.get_user_balance(ask["user"], quote_asset)
        let ask_base_bal = self.get_user_balance(ask["user"], base)

        let cost = bi.bi_mul(amount, price)

        self.set_user_balance(bid["user"], quote_asset, bi.bi_sub(bid_quote_bal, cost))
        self.set_user_balance(bid["user"], base, bi.bi_add(bid_base_bal, amount))
        self.set_user_balance(ask["user"], quote_asset, bi.bi_add(ask_quote_bal, cost))
        self.set_user_balance(ask["user"], base, bi.bi_sub(ask_base_bal, amount))

        print("Trade executed: " + amount + " " + base + " @ " + price + " " + quote_asset)

    proc sort_orders(self, orders, direction):
        # Simple bubble sort for deterministic ordering
        let n = len(orders)
        let arr = orders
        var i = 0
        while i < n:
            var j = 0
            while j < n - i - 1:
                let a = int(arr[j]["price"])
                let b = int(arr[j + 1]["price"])
                let swap = false
                if direction == "desc" and a < b:
                    swap = true
                if direction == "asc" and a > b:
                    swap = true
                if swap:
                    let tmp = arr[j]
                    arr[j] = arr[j + 1]
                    arr[j + 1] = tmp
                j = j + 1
            i = i + 1
        return arr

    # Query methods
    proc get_order_book(self, market, depth = 20):
        if not dict_has(self.order_book, market):
            return {"error": "Market not found"}
        let ob = self.order_book[market]
        let bids = []
        let asks = []
        var i = 0
        let max_bids = _min(depth, len(ob["bids"]))
        while i < max_bids:
            push(bids, {"price": ob["bids"][i]["price"], "amount": bi.bi_sub(ob["bids"][i]["amount"], ob["bids"][i]["filled"])})
            i = i + 1
        i = 0
        let max_asks = _min(depth, len(ob["asks"]))
        while i < max_asks:
            push(asks, {"price": ob["asks"][i]["price"], "amount": bi.bi_sub(ob["asks"][i]["amount"], ob["asks"][i]["filled"])})
            i = i + 1
        return {"bids": bids, "asks": asks}

    proc get_user_orders(self, market, user):
        if not dict_has(self.order_book, market):
            return []
        let out = []
        for o in self.order_book[market]["bids"]:
            if o["user"] == user:
                push(out, o)
        for o in self.order_book[market]["asks"]:
            if o["user"] == user:
                push(out, o)
        return out

    proc get_recent_trades(self, market, limit = 50):
        # In v1, trades are logged to console; a proper implementation would store them
        return {"trades": [], "note": "Trade history not yet persisted in v1"}

proc create_exchange(chain):
    let ex = ExchangeClient(chain)
    # Create default markets
    ex.create_market("ORBIT", "USD")
    ex.create_market("ORBIT", "BTC")
    ex.create_market("ORBIT", "ETH")
    return ex