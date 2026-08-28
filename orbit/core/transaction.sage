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
let POOL_SENDER = "__mining_pool__"
let MEMO_MAX = 128

let KNOWN_KINDS = [KIND_TRANSFER, KIND_REWARD]

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

proc encode_unsigned(tx):
    return encoding.encode_canonical(canonical_fields(tx))
