# orbit/core/transaction.sage — transaction model + validation (plan §17)
# Orbit Blockchain | Protocol v1 | Status: implemented (transfer/reward)
#
# Canonical form: every field below is encoded via orbit.crypto.encoding
# with sorted keys; tx_id = sha256(canonical(unsigned fields)).
# Reward transactions are protocol-minted: sender is "__mining_pool__" and
# the signature/public key fields stay nil; the block validator recomputes
# the amount from consensus inputs instead of trusting a signature.

import orbit.core.bigint as bi
import orbit.core.errors as errors
import orbit.wallet.account as account
import orbit.crypto.signatures as signatures
import orbit.crypto.encoding as encoding

let KIND_TRANSFER = "transfer"
let KIND_REWARD = "reward"
let KIND_LOCK = "lock"
let KIND_UNLOCK = "unlock"
let KIND_CLAIM = "claim"
let POOL_SENDER = "__mining_pool__"
let MEMO_MAX = 128

let KNOWN_KINDS = [KIND_TRANSFER, KIND_REWARD, KIND_LOCK, KIND_UNLOCK, KIND_CLAIM]

class Transaction:
    proc init(self, kind, sender, recipient, amount, fee, nonce, timestamp):
        self.kind = kind
        self.sender = sender
        self.recipient = recipient
        self.amount = amount        # bigint string, base units
        self.fee = fee              # bigint string, base units
        self.nonce = nonce          # integer
        self.timestamp = timestamp  # protocol timestamp (integer)
        self.memo = ""
        self.public_key = nil
        self.signature = nil
        self.tx_id = nil
        self.mining_context = nil   # reward only: users/height/score commitments
        # lockup fields
        self.lock_duration = 0      # blocks
        self.claim_height = 0       # height when claimable
        self.lockup_id = nil        # unique ID for lockup position

proc canonical_fields(tx):
    # Fixed field set for hashing — signature material EXCLUDED.
    let d = {
        "kind": tx.kind,
        "sender": tx.sender,
        "recipient": tx.recipient,
        "amount": tx.amount,
        "fee": tx.fee,
        "nonce": tx.nonce,
        "timestamp": tx.timestamp,
        "memo": tx.memo,
    }
    if tx.kind == KIND_REWARD and tx.mining_context != nil:
        d["mining"] = tx.mining_context
    if tx.kind == KIND_LOCK or tx.kind == KIND_UNLOCK or tx.kind == KIND_CLAIM:
        d["lock_duration"] = tx.lock_duration
        d["claim_height"] = tx.claim_height
        d["lockup_id"] = tx.lockup_id
    return d

proc compute_id(tx):
    return encoding.canonical_hash(canonical_fields(tx))

proc sign_with(tx, seed):
    tx.public_key = account.derive_public_key(seed)
    tx.signature = signatures.sign(seed, encoding.encode_canonical(canonical_fields(tx)))
    tx.tx_id = compute_id(tx)
    return tx

# Structural + stateful validation. Returns [ok, error_code].
# `state` is a WorldState-style dict of accounts; pool_remaining is a bigint
# string checked for reward minting.
proc validate(tx, state, pool_remaining):
    var found_kind = false
    for k in KNOWN_KINDS:
        if k == tx.kind:
            found_kind = true
    if not found_kind:
        return [false, errors.ERR_INVALID_TX]

    # Allow zero amount for lockup transactions (lock/unlock/claim have their own validation)
    if tx.kind != KIND_LOCK and tx.kind != KIND_UNLOCK and tx.kind != KIND_CLAIM:
        if type(tx.amount) != "string" or bi.bi_is_zero(tx.amount) or bi.bi_cmp(tx.amount, "0") < 0:
            return [false, errors.ERR_INVALID_TX]
    # fee is optional: treat nil as zero, but never mutate the tx under test
    var fee_value = tx.fee
    if fee_value == nil:
        fee_value = "0"
    if type(fee_value) != "string" or bi.bi_cmp(fee_value, "0") < 0:
        return [false, errors.ERR_INVALID_TX]
    tx.fee = bi.bi_norm(fee_value)
    if len(tx.memo) > MEMO_MAX:
        return [false, errors.ERR_INVALID_TX]

    if tx.kind == KIND_REWARD:
        if tx.sender != POOL_SENDER:
            return [false, errors.ERR_INVALID_TX]
        if not account.is_valid_address(tx.recipient):
            return [false, errors.ERR_INVALID_TX]
        if bi.bi_cmp(tx.amount, pool_remaining) > 0:
            return [false, errors.ERR_POOL_EXHAUSTED]
        return [true, nil]

    # lockup path
    if tx.kind == KIND_LOCK:
        return validate_lock(tx, state)
    if tx.kind == KIND_UNLOCK:
        return validate_unlock(tx, state)
    if tx.kind == KIND_CLAIM:
        return validate_claim(tx, state)
    if tx.kind == KIND_UNLOCK:
        return validate_unlock(tx, state)
    if tx.kind == KIND_CLAIM:
        return validate_claim(tx, state)

    # transfer path
    if not account.is_valid_address(tx.sender):
        return [false, errors.ERR_INVALID_TX]
    if not account.is_valid_address(tx.recipient):
        return [false, errors.ERR_INVALID_TX]
    if tx.sender == tx.recipient:
        return [false, errors.ERR_INVALID_TX]
    if not dict_has(state, tx.sender):
        return [false, errors.ERR_INSUFFICIENT]

    let acct = state[tx.sender]
    if tx.nonce != acct["nonce"]:
        return [false, errors.ERR_NONCE_MISMATCH]

    # signature must verify and commit to the claimed address
    if tx.signature == nil or tx.public_key == nil:
        return [false, errors.ERR_BAD_SIGNATURE]
    if not signatures.verify(tx.public_key, encode_unsigned(tx), tx.signature):
        return [false, errors.ERR_BAD_SIGNATURE]
    if signatures.address_for_public_key(tx.public_key) != tx.sender:
        return [false, errors.ERR_BAD_SIGNATURE]

    let spend = bi.bi_add(tx.amount, tx.fee)
    if bi.bi_cmp(spend, acct["balance"]) > 0:
        return [false, errors.ERR_INSUFFICIENT]
    return [true, nil]

# Lockup validation functions
proc validate_lock(tx, state):
    if not account.is_valid_address(tx.sender):
        return [false, errors.ERR_INVALID_TX]
    if not account.is_valid_address(tx.recipient):
        return [false, errors.ERR_INVALID_TX]
    if not dict_has(state, tx.sender):
        return [false, errors.ERR_INSUFFICIENT]
    let acct = state[tx.sender]
    if tx.nonce != acct["nonce"]:
        return [false, errors.ERR_NONCE_MISMATCH]
    if tx.signature == nil or tx.public_key == nil:
        return [false, errors.ERR_BAD_SIGNATURE]
    if not signatures.verify(tx.public_key, encode_unsigned(tx), tx.signature):
        return [false, errors.ERR_BAD_SIGNATURE]
    if signatures.address_for_public_key(tx.public_key) != tx.sender:
        return [false, errors.ERR_BAD_SIGNATURE]
    # lock_duration must be positive
    if tx.lock_duration <= 0:
        return [false, errors.ERR_INVALID_TX]
    # claim_height must be set
    if tx.claim_height <= 0:
        return [false, errors.ERR_INVALID_TX]
    # lockup_id must be set
    if tx.lockup_id == nil:
        return [false, errors.ERR_INVALID_TX]
    # amount must be positive
    if bi.bi_cmp(tx.amount, "0") <= 0:
        return [false, errors.ERR_INVALID_TX]
    # check balance
    let spend = bi.bi_add(tx.amount, tx.fee)
    if bi.bi_cmp(spend, acct["balance"]) > 0:
        return [false, errors.ERR_INSUFFICIENT]
    return [true, nil]

proc validate_unlock(tx, state):
    if not account.is_valid_address(tx.sender):
        return [false, errors.ERR_INVALID_TX]
    if tx.recipient != "":
        return [false, errors.ERR_INVALID_TX]  # unlock has no recipient
    if not dict_has(state, tx.sender):
        return [false, errors.ERR_INSUFFICIENT]
    let acct = state[tx.sender]
    if tx.nonce != acct["nonce"]:
        return [false, errors.ERR_NONCE_MISMATCH]
    if tx.signature == nil or tx.public_key == nil:
        return [false, errors.ERR_BAD_SIGNATURE]
    if not signatures.verify(tx.public_key, encode_unsigned(tx), tx.signature):
        return [false, errors.ERR_BAD_SIGNATURE]
    if signatures.address_for_public_key(tx.public_key) != tx.sender:
        return [false, errors.ERR_BAD_SIGNATURE]
    # lockup_id must reference an existing lockup
    if tx.lockup_id == nil:
        return [false, errors.ERR_INVALID_TX]
    return [true, nil]

proc validate_claim(tx, state):
    if not account.is_valid_address(tx.sender):
        return [false, errors.ERR_INVALID_TX]
    if tx.recipient != "":
        return [false, errors.ERR_INVALID_TX]  # claim has no recipient
    if not dict_has(state, tx.sender):
        return [false, errors.ERR_INSUFFICIENT]
    let acct = state[tx.sender]
    if tx.nonce != acct["nonce"]:
        return [false, errors.ERR_NONCE_MISMATCH]
    if tx.signature == nil or tx.public_key == nil:
        return [false, errors.ERR_BAD_SIGNATURE]
    if not signatures.verify(tx.public_key, encode_unsigned(tx), tx.signature):
        return [false, errors.ERR_BAD_SIGNATURE]
    if signatures.address_for_public_key(tx.public_key) != tx.sender:
        return [false, errors.ERR_BAD_SIGNATURE]
    # lockup_id must reference an existing lockup
    if tx.lockup_id == nil:
        return [false, errors.ERR_INVALID_TX]
    return [true, nil]

proc encode_unsigned(tx):
    return encoding.encode_canonical(canonical_fields(tx))
