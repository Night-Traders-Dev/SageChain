# orbit/core/errors.sage — protocol error codes and messages
# Orbit Blockchain | Protocol v1 | Status: skeleton


let ERR_INVALID_TX       = "invalid_transaction"
let ERR_BAD_SIGNATURE    = "bad_signature"
let ERR_NONCE_MISMATCH   = "nonce_mismatch"
let ERR_INSUFFICIENT     = "insufficient_balance"
let ERR_BAD_BLOCK        = "malformed_block"
let ERR_LINK_BROKEN      = "previous_hash_mismatch"
let ERR_REPLAY           = "replayed_transaction"
let ERR_POOL_EXHAUSTED   = "mining_pool_exhausted"

proc describe(code):
    return code
