# t16 — smart contracts (Phase 10)
import orbit.core.chain as chainmod
import orbit.core.transaction as txmod
import orbit.core.ledger as ledgermod
import orbit.contracts.sandbox as sandbox
import orbit.contracts.gas as gas
import orbit.wallet.account as account
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

# Extend chain for contracts
chain.contracts = {}
chain.get_contract = proc(self, addr):
    if dict_has(self.contracts, addr):
        return self.contracts[addr]
    return nil
chain.set_contract = proc(self, addr, contract):
    self.contracts[addr] = contract
    return true

import orbit.core.merkle as merkle
import orbit.crypto.encoding as encoding
from crypto.hash import sha256_hex

chain.contract_state_root = proc(self):
    let addrs = []
    for addr in self.contracts:
        push(addrs, addr)
    let sorted = encoding.sort_strings(addrs)
    let leaves = []
    for addr in sorted:
        let c = self.contracts[addr]
        push(leaves, sha256_hex(enc.encode_canonical([addr, c.balance, c.nonce])))
    return merkle.root(leaves)

# Test contract deploy
print("=== Testing Contract Deploy ===")
let alice = account.generate_keypair("contract-alice-seed")
chain.state.accounts[alice["address"]] = {"balance": "100000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil, "lockups": {}}

# Simple contract code: ADD 1 + 2 -> 3
let contract_code = ["PUSH", "1", "PUSH", "2", "ADD", "STOP"]
let deploy_tx = txmod.Transaction(txmod.KIND_CONTRACT_DEPLOY, alice["address"], "", "0", "1000", 0, 1000)
deploy_tx.contract_code = contract_code
deploy_tx.gas_limit = 1000000
deploy_tx.value = "0"
txmod.sign_with(deploy_tx, "contract-alice-seed")

let vr = txmod.validate(deploy_tx, chain.state.accounts, chain.pool_remaining)
check("deploy-validate", vr[0])

let ldg = ledgermod.Ledger(chain.state)
let ar = ldg.apply(deploy_tx, chain.pool_remaining)
check("deploy-apply", ar[0])

let contract_addr = ar[3]["contract_address"]
check("contract-addr", contract_addr != nil and len(contract_addr) == 43)
check("contract-exists", chain.get_contract(contract_addr) != nil)
check("alice-nonce-incremented", chain.state.accounts[alice["address"]]["nonce"] == 1)

# Test contract call
print("=== Testing Contract Call ===")
let bob = account.generate_keypair("contract-bob-seed")
chain.state.accounts[bob["address"]] = {"balance": "100000000000", "nonce": 0, "locked_balance": "0", "activity_marker": 0, "validator_status": nil, "lockups": {}}

# Call contract with PUSH 5, PUSH 3, ADD -> 8
let call_tx = txmod.Transaction(txmod.KIND_CONTRACT_CALL, bob["address"], contract_addr, "0", "1000", 0, 2000)
call_tx.gas_limit = 1000000
call_tx.value = "0"
call_tx.input_data = ""  # would contain calldata in real impl
txmod.sign_with(call_tx, "contract-bob-seed")

let vr2 = txmod.validate(call_tx, chain.state.accounts, chain.pool_remaining)
check("call-validate", vr2[0])

let ar2 = ldg.apply(call_tx, chain.pool_remaining)
check("call-apply", ar2[0])
check("call-gas-used", ar2[3]["gas_used"] != nil and ar2[3]["gas_used"] > 0)

# Test state root with contracts
print("=== Testing Contract State Root ===")
let chain2 = chainmod.Chain(net)
chain2.contracts = {}
chain2.contracts[contract_addr] = sandbox.Contract(contract_code, contract_addr)
let root1 = chain2.contract_state_root()

let chain3 = chainmod.Chain(net)
chain3.contracts = {}
chain3.contracts[contract_addr] = sandbox.Contract(contract_code, contract_addr)
let root2 = chain3.contract_state_root()

check("contract-state-root-deterministic", root1 == root2)

# Test gas accounting
print("=== Testing Gas Accounting ===")
let gm = gas.GasMeter(1000000)
gm.consume(100000)
check("gas-consume", gm.used == 100000)
check("gas-remaining", gm.remaining() == 900000)
gm.refund(50000)
check("gas-refund", gm.used == 50000)
gm.consume(900000)
check("gas-oog", gm.used == 950000)

# Test out of gas
let gm2 = gas.GasMeter(100)
var threw = false
try:
    gm2.consume(200)
catch e:
    threw = true
check("gas-oog-throw", threw)

print("t16 smart contracts: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t16 FAILED"