# orbit/contracts/gas.sage — Gas accounting for smart contracts (§35)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet)

import orbit.core.bigint as bi

let GAS_LIMIT_DEFAULT = 10000000
let GAS_COST_BASE = 100
let GAS_COST_STORAGE_READ = 200
let GAS_COST_STORAGE_WRITE = 5000
let GAS_COST_MEMORY_EXPAND = 50
let GAS_COST_CALL = 700
let GAS_COST_HASH = 500
let GAS_COST_LOG = 375

proc estimate_gas(ops):
    let total = 0
    for op in ops:
        if op == "base":
            total = total + GAS_COST_BASE
        if op == "storage_read":
            total = total + GAS_COST_STORAGE_READ
        if op == "storage_write":
            total = total + GAS_COST_STORAGE_WRITE
        if op == "memory_expand":
            total = total + GAS_COST_MEMORY_EXPAND
        if op == "call":
            total = total + GAS_COST_CALL
        if op == "hash":
            total = total + GAS_COST_HASH
        if op == "log":
            total = total + GAS_COST_LOG
    return total

proc calc_gas_cost(opcode, args = nil):
    if opcode == "STOP" or opcode == "RETURN":
        return 0
    if opcode == "ADD" or opcode == "SUB" or opcode == "MUL" or opcode == "DIV" or opcode == "MOD":
        return 5
    if opcode == "LT" or opcode == "GT" or opcode == "EQ" or opcode == "AND" or opcode == "OR" or opcode == "XOR":
        return 3
    if opcode == "SHA3":
        return GAS_COST_HASH
    if opcode == "SLOAD":
        return GAS_COST_STORAGE_READ
    if opcode == "SSTORE":
        return GAS_COST_STORAGE_WRITE
    if opcode == "MLOAD" or opcode == "MSTORE" or opcode == "MSTORE8":
        return 3
    if opcode == "JUMP" or opcode == "JUMPI":
        return 8
    if opcode == "CALL" or opcode == "CALLCODE" or opcode == "DELEGATECALL" or opcode == "STATICCALL":
        return GAS_COST_CALL
    if opcode == "CREATE":
        return 32000
    if opcode == "LOG0" or opcode == "LOG1" or opcode == "LOG2" or opcode == "LOG3" or opcode == "LOG4":
        return GAS_COST_LOG
    if opcode == "EXP":
        return 50
    return GAS_COST_BASE

class GasMeter:
    proc init(self, limit):
        self.limit = limit
        self.used = 0

    proc consume(self, amount):
        self.used = self.used + amount
        if self.used > self.limit:
            raise "out_of_gas"
        return true

    proc remaining(self):
        return self.limit - self.used

    proc refund(self, amount):
        if amount > self.used:
            self.used = 0
        else:
            self.used = self.used - amount
        return true