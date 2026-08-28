# orbit/consensus/voting.sage — signed votes + weighted tallying (plan §15)
# Orbit Blockchain | Protocol v1 | Status: implemented (v1 weight formula)
#
# Pinned weight formula (Phase 0 freeze item):
#     VoteWeight = BASE_WEIGHT * trust * uptime / MAX^2     (integer floor)
# i.e. equal-suffrage baseline scaled by trust and uptime on the 10^6 grid.
# Weight range: [0, BASE]. Pending/slashed validators weigh zero.
#
# Votes are Lamport-signed over canonical vote fields and are ONE-TIME —
# a validator rotates its seed per vote in this devnet scheme.

import orbit.core.bigint as bi
import orbit.crypto.signatures as signatures
import orbit.crypto.encoding as encoding

let BASE_WEIGHT = 1000000
let VOTE_YES = "yes"
let VOTE_NO = "no"

class Vote:
    proc init(self, validator_addr, block_hash, height, choice):
        self.validator_addr = validator_addr
        self.block_hash = block_hash
        self.height = height
        self.choice = choice       # "yes" | "no"
        self.public_key = nil
        self.signature = nil

proc canonical_fields(v):
    return {
        "validator_addr": v.validator_addr,
        "block_hash": v.block_hash,
        "height": v.height,
        "choice": v.choice,
    }

# The public key of a Lamport identity is derived from its seed; votes carry
# the full 64-leaf key so any node verifies without extra state.
proc sign_vote(v, seed):
    import orbit.wallet.account as account
    v.public_key = account.derive_public_key(seed)
    v.signature = signatures.sign(seed,
        encoding.encode_canonical(canonical_fields(v)))
    return v

# Structural + cryptographic validation against the registry.
# Returns [ok, err].
proc validate(v, registry):
    if not registry.has(v.validator_addr):
        return [false, "unknown_validator"]
    let rec = registry.get(v.validator_addr)
    if rec["current_status"] != "active":
        return [false, "not_active"]
    if v.choice != VOTE_YES and v.choice != VOTE_NO:
        return [false, "bad_choice"]
    if v.signature == nil or v.public_key == nil:
        return [false, "bad_signature"]
    if not signatures.verify(v.public_key,
                             encoding.encode_canonical(canonical_fields(v)),
                             v.signature):
        return [false, "bad_signature"]
    # the signing identity must commit to the validator's registered address
    import orbit.wallet.account as account
    if account.derive_address_from_public_key(v.public_key) != v.validator_addr:
        return [false, "bad_signature"]
    return [true, nil]

# Deterministic tally. votes must be pre-validated; duplicates are rejected
# by (addr, block_hash) uniqueness.
proc tally(votes, registry, block_hash, height):
    # Precondition: votes already deduplicated + validated by poi.evaluate_candidate.
    var total = 0
    var yes = 0
    for v in votes:
        let w = weight_for(registry, v.validator_addr)
        total = total + w
        if v.block_hash == block_hash and v.height == height and v.choice == VOTE_YES:
            yes = yes + w
    return {"yes": yes, "total": total}

proc weight_for(registry, addr):
    if not registry.has(addr):
        return 0
    let v = registry.get(addr)
    if v["current_status"] != "active":
        return 0
    let tw = v["trust_score"]
    let uw = v["uptime_score"]
    let num = bi.bi_mul(bi.bi_from_number(BASE_WEIGHT),
                        bi.bi_mul(bi.bi_from_number(tw), bi.bi_from_number(uw)))
    let den = bi.bi_mul("1000000", "1000000")
    return bi.bi_to_number(bi.bi_div(num, den))

