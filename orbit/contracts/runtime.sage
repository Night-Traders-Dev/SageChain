# orbit/contracts/runtime.sage — Orbim contract runtime (§35)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.contracts.sandbox as sandbox
import orbit.contracts.gas as gas
import orbit.core.chain as chainmod
import orbit.core.transaction as txmod
import orbit.core.state as statemod
import orbit.core.ledger as ledgermod
import orbit.core.bigint as bi
import orbit.crypto.encoding as enc

# Contract transaction kinds
let KIND_CONTRACT_DEPLOY = "contract_deploy"
let KIND_CONTRACT_CALL = "contract_call"

# Deploy validation
proc validate_deploy(tx, state, pool_remaining):
    if not txmod.account.is_valid_address(tx.sender):
        return [false, txmod.errors.ERR_INVALID_TX]
    if not dict_has(state, tx.sender):
        return [false, txmod.errors.ERR_INSUFFICIENT]
    let acct = state[tx.sender]
    if tx.nonce != acct["nonce"]:
        return [false, txmod.errors.ERR_NONCE_MISMATCH]
    if tx.signature == nil or tx.public_key == nil:
        return [false, txmod.errors.ERR_BAD_SIGNATURE]
    if not txmod.signatures.verify(tx.public_key, txmod.encode_unsigned(tx), tx.signature):
        return [false, txmod.errors.ERR_BAD_SIGNATURE]
    if txmod.signatures.address_for_public_key(tx.public_key) != tx.sender:
        return [false, txmod.errors.ERR_BAD_SIGNATURE]
    if tx.contract_code == nil or len(tx.contract_code) > sandbox.MAX_CONTRACT_SIZE:
        return [false, txmod.errors.ERR_INVALID_TX]
    if tx.gas_limit == nil or tx.gas_limit <= 0:
        return [false, txmod.errors.ERR_INVALID_TX]
    if bi.bi_cmp(tx.value, "0") < 0:
        return [false, txmod.errors.ERR_INVALID_TX]
    let spend = bi.bi_add(tx.value, tx.fee)
    if bi.bi_cmp(spend, acct["balance"]) > 0:
        return [false, txmod.errors.ERR_INSUFFICIENT]
    return [true, nil]

# Call validation
proc validate_call(tx, state, pool_remaining):
    if not txmod.account.is_valid_address(tx.sender):
        return [false, txmod.errors.ERR_INVALID_TX]
    if not txmod.account.is_valid_address(tx.recipient):
        return [false, txmod.errors.ERR_INVALID_TX]
    if not dict_has(state, tx.sender):
        return [false, txmod.errors.ERR_INSUFFICIENT]
    let acct = state[tx.sender]
    if tx.nonce != acct["nonce"]:
        return [false, txmod.errors.ERR_NONCE_MISMATCH]
    if tx.signature == nil or tx.public_key == nil:
        return [false, txmod.errors.ERR_BAD_SIGNATURE]
    if not txmod.signatures.verify(tx.public_key, txmod.encode_unsigned(tx), tx.signature):
        return [false, txmod.errors.ERR_BAD_SIGNATURE]
    if txmod.signatures.address_for_public_key(tx.public_key) != tx.sender:
        return [false, txmod.errors.ERR_BAD_SIGNATURE]
    if tx.gas_limit == nil or tx.gas_limit <= 0:
        return [false, txmod.errors.ERR_INVALID_TX]
    if bi.bi_cmp(tx.value, "0") < 0:
        return [false, txmod.errors.ERR_INVALID_TX]
    let spend = bi.bi_add(tx.value, tx.fee)
    if bi.bi_cmp(spend, acct["balance"]) > 0:
        return [false, txmod.errors.ERR_INSUFFICIENT]
    return [true, nil]

# Apply deploy
proc apply_deploy(chain, tx, pool_remaining):
    let contract_addr = sandbox.generate_contract_address(tx.sender, tx.nonce)
    let contract = sandbox.Contract(tx.contract_code, contract_addr)
    chain.set_contract(contract_addr, contract)

    let sender_acct = chain.state.get(tx.sender)
    let spend = bi.bi_add(tx.value, tx.fee)
    sender_acct["balance"] = bi.bi_sub(sender_acct["balance"], spend)
    sender_acct["nonce"] = sender_acct["nonce"] + 1
    sender_acct["activity_marker"] = tx.timestamp

    if bi.bi_cmp(tx.value, "0") > 0:
        contract.add_balance(tx.value)

    return [true, nil, pool_remaining, {"contract_address": contract_addr}]

# Apply call
proc apply_call(chain, tx, pool_remaining):
    let contract_addr = tx.recipient
    let contract = chain.get_contract(contract_addr)
    if contract == nil:
        return [false, "contract_not_found", pool_remaining]

    let sender_acct = chain.state.get(tx.sender)
    let spend = bi.bi_add(tx.value, tx.fee)
    sender_acct["balance"] = bi.bi_sub(sender_acct["balance"], spend)
    sender_acct["nonce"] = sender_acct["nonce"] + 1
    sender_acct["activity_marker"] = tx.timestamp

    if bi.bi_cmp(tx.value, "0") > 0:
        sender_acct["balance"] = bi.bi_sub(sender_acct["balance"], tx.value)
        contract.add_balance(tx.value)

    let gas_limit = tx.gas_limit
    let gas_meter = gas.GasMeter(gas_limit)

    let result = sandbox.execute_contract(chain, {
        "recipient": contract_addr,
        "sender": tx.sender,
        "value": tx.value,
        "gas_limit": gas_limit,
        "input_data": tx.input_data,
        "contract_code": nil,
    }, pool_remaining)

    return result

# Extended transaction validation
proc validate_extended(tx, state, pool_remaining):
    if tx.kind == KIND_CONTRACT_DEPLOY:
        return validate_deploy(tx, state, pool_remaining)
    if tx.kind == KIND_CONTRACT_CALL:
        return validate_call(tx, state, pool_remaining)
    return txmod.validate(tx, state, pool_remaining)

# Extended ledger apply
proc apply_extended(chain, tx, pool_remaining):
    if tx.kind == KIND_CONTRACT_DEPLOY:
        return apply_deploy(chain, tx, pool_remaining)
    if tx.kind == KIND_CONTRACT_CALL:
        return apply_call(chain, tx, pool_remaining)
    return chain.ledger.apply(tx, pool_remaining)

# Contract state integration with chain
proc extend_chain_for_contracts(chain):
    chain.contracts = {}
    chain.contract_state_root = sandbox.contract_state_root

    proc get_contract(self, addr):
        if dict_has(self.contracts, addr):
            return self.contracts[addr]
        return nil

    proc set_contract(self, addr, contract):
        self.contracts[addr] = contract
        return true

    proc contract_state_root(self):
        import orbit.core.merkle as merkle
        import orbit.crypto.encoding as encoding
        from crypto.hash import sha256_hex
        let addrs = []
        for addr in self.contracts:
            push(addrs, addr)
        let sorted = encoding.sort_strings(addrs)
        let leaves = []
        for addr in sorted:
            let c = self.contracts[addr]
            push(leaves, sha256_hex(enc.encode_canonical([addr, c.balance, c.nonce])))
        return merkle.root(leaves)

    chain.get_contract = get_contract
    chain.set_contract = set_contract
    chain.contract_state_root = contract_state_root

    return chain