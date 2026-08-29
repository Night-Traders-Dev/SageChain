# orbit/contracts/sandbox.sage — Deterministic WASM sandbox (§35)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.contracts.gas as gas
import orbit.core.bigint as bi
import orbit.crypto.encoding as enc
from crypto.hash import sha256_hex

let MAX_CONTRACT_SIZE = 1048576
let MAX_MEMORY_PAGES = 1024
let MAX_STACK_SIZE = 1024

class Contract:
    proc init(self, code, address):
        self.code = code
        self.address = address
        self.storage = {}
        self.balance = "0"
        self.nonce = 0

    proc get_storage(self, key):
        if dict_has(self.storage, key):
            return self.storage[key]
        return "0"

    proc set_storage(self, key, value):
        self.storage[key] = value
        return true

    proc get_balance(self):
        return self.balance

    proc add_balance(self, amount):
        self.balance = bi.bi_add(self.balance, amount)
        return true

    proc sub_balance(self, amount):
        if bi.bi_cmp(self.balance, amount) < 0:
            return false
        self.balance = bi.bi_sub(self.balance, amount)
        return true

# Simple stack-based VM for deterministic execution
class VMState:
    proc init(self, contract, gas_meter, caller, value, input_data):
        self.contract = contract
        self.gas = gas_meter
        self.caller = caller
        self.value = value
        self.input = input_data
        self.memory = []
        self.stack = []
        self.pc = 0
        self.depth = 0
        self.return_data = []

    proc push_stack(self, val):
        if len(self.stack) >= MAX_STACK_SIZE:
            raise "stack_overflow"
        push(self.stack, val)
        return true

    proc pop_stack(self):
        if len(self.stack) == 0:
            raise "stack_underflow"
        let val = self.stack[len(self.stack) - 1]
        self.stack = self.stack[:len(self.stack) - 1]
        return val

    proc peek_stack(self, idx = 0):
        if idx >= len(self.stack):
            return "0"
        return self.stack[len(self.stack) - 1 - idx]

    proc expand_memory(self, offset, size):
        let end = offset + size
        let pages_needed = (end + 65535) / 65536
        if pages_needed > MAX_MEMORY_PAGES:
            raise "memory_limit_exceeded"
        if pages_needed > len(self.memory) / 65536:
            self.gas.consume(gas.GAS_COST_MEMORY_EXPAND * (pages_needed - len(self.memory) / 65536))
        while len(self.memory) < end:
            push(self.memory, 0)
        return true

    proc memory_load(self, offset, size):
        self.expand_memory(offset, size)
        let result = ""
        var i = 0
        while i < size:
            result = result + chr(self.memory[offset + i])
            i = i + 1
        return result

    proc memory_store(self, offset, data):
        self.expand_memory(offset, len(data))
        var i = 0
        while i < len(data):
            self.memory[offset + i] = ord(data[i])
            i = i + 1
        return true

# Contract deployment transaction
proc create_deploy_tx(sender, code, gas_limit, value, nonce, timestamp, fee, seed):
    import orbit.core.transaction as txmod
    let tx = txmod.Transaction(txmod.KIND_CONTRACT_DEPLOY, sender, "", "0", str(fee), nonce, timestamp)
    tx.contract_code = code
    tx.gas_limit = gas_limit
    tx.value = value
    txmod.sign_with(tx, seed)
    return tx

# Contract call transaction
proc create_call_tx(sender, contract_addr, gas_limit, value, input_data, nonce, timestamp, fee, seed):
    import orbit.core.transaction as txmod
    let tx = txmod.Transaction(txmod.KIND_CONTRACT_CALL, sender, contract_addr, "0", str(fee), nonce, timestamp)
    tx.gas_limit = gas_limit
    tx.value = value
    tx.input_data = input_data
    txmod.sign_with(tx, seed)
    return tx

# Execution engine
proc execute_contract(chain, tx, pool_remaining):
    # Get or create contract
    let contract_addr = tx.recipient
    let contract = chain.get_contract(contract_addr)
    if contract == nil:
        if tx.kind == "contract_deploy":
            # Create new contract
            contract_addr = generate_contract_address(tx.sender, tx.nonce)
            contract = Contract(tx.contract_code, contract_addr)
            chain.set_contract(contract_addr, contract)
        else:
            return [false, "contract_not_found", pool_remaining]

    # Transfer value
    if bi.bi_cmp(tx.value, "0") > 0:
        let sender_acct = chain.state.get(tx.sender)
        if bi.bi_cmp(sender_acct["balance"], tx.value) < 0:
            return [false, "insufficient_balance", pool_remaining]
        sender_acct["balance"] = bi.bi_sub(sender_acct["balance"], tx.value)
        contract.add_balance(tx.value)

    # Setup gas
    let gas_limit = gas.GAS_LIMIT_DEFAULT
    if tx.gas_limit != nil:
        gas_limit = tx.gas_limit
    let gas_meter = gas.GasMeter(gas_limit)

    # Setup VM
    let vm = VMState(contract, gas_meter, tx.sender, tx.value, tx.input_data)

    # Execute bytecode
    let result = execute_bytecode(vm)

    # Refund unused gas (simplified)
    let gas_used = gas_meter.used
    let gas_refund = gas_meter.remaining() / 2
    gas_meter.refund(gas_refund)

    # Commit state changes
    chain.set_contract(contract_addr, contract)

    return [result[0], result[1], pool_remaining, {"gas_used": gas_used, "return_data": vm.return_data}]

proc execute_bytecode(vm):
    # Simplified bytecode execution - in production this would be a full WASM interpreter
    # For devnet, we implement a minimal instruction set
    while vm.pc < len(vm.contract.code):
        let op = vm.contract.code[vm.pc]
        vm.pc = vm.pc + 1

        # Consume base gas
        let cost = gas.calc_gas_cost(op)
        if cost > 0:
            vm.gas.consume(cost)

        # Execute instruction
        if op == "STOP" or op == "RETURN":
            return [true, "success"]
        if op == "PUSH":
            # PUSH <value> - push next item onto stack
            if vm.pc < len(vm.contract.code):
                let val = vm.contract.code[vm.pc]
                vm.pc = vm.pc + 1
                vm.push_stack(val)
            else:
                raise "push_underflow"
            continue
        if op == "ADD":
            let a = vm.pop_stack()
            let b = vm.pop_stack()
            vm.push_stack(str(int(a) + int(b)))
        elif op == "SUB":
            let a = vm.pop_stack()
            let b = vm.pop_stack()
            vm.push_stack(str(int(a) - int(b)))
        elif op == "MUL":
            let a = vm.pop_stack()
            let b = vm.pop_stack()
            vm.push_stack(str(int(a) * int(b)))
        elif op == "EQ":
            let a = vm.pop_stack()
            let b = vm.pop_stack()
            let eq_result = "0"
            if a == b:
                eq_result = "1"
            vm.push_stack(eq_result)
        elif op == "SLOAD":
            let key = vm.pop_stack()
            vm.push_stack(vm.contract.get_storage(key))
        elif op == "SSTORE":
            let key = vm.pop_stack()
            let value = vm.pop_stack()
            vm.contract.set_storage(key, value)
        elif op == "SHA3":
            let offset = int(vm.pop_stack())
            let size = int(vm.pop_stack())
            let data = vm.memory_load(offset, size)
            vm.push_stack(sha256_hex(data))
        elif op == "LOG0" or op == "LOG1" or op == "LOG2" or op == "LOG3" or op == "LOG4":
            # Simplified logging
            pass
        else:
            # Unknown opcode - consume gas and continue
            pass
    return [true, "execution_completed"]

proc generate_contract_address(sender, nonce):
    import orbit.crypto.encoding as enc
    from crypto.hash import sha256_hex
    let parts = enc.encode_canonical([sender, str(nonce)])
    let hash = sha256_hex(parts)
    return "orb:" + hash[:40]

# Contract state root
proc contract_state_root(chain):
    import orbit.core.merkle as merkle
    import orbit.crypto.encoding as encoding
    let addrs = []
    for addr in chain.contracts:
        push(addrs, addr)
    let sorted = encoding.sort_strings(addrs)
    let leaves = []
    for addr in sorted:
        let c = chain.contracts[addr]
        push(leaves, sha256_hex(enc.encode_canonical([addr, c.balance, c.nonce])))
    return merkle.root(leaves)