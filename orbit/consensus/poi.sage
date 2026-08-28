# orbit/consensus/poi.sage — Proof-of-Insight proposal pipeline (plan §15)
# Orbit Blockchain | Protocol v1 | Status: implemented (single-node devnet)
#
# v1 flow implemented here: collect signed votes for a candidate hash ->
# validate against registry -> tally with pinned weights -> certificate.
# Proposer rotation (§15) lands with multi-node networking in Phase 5.

import orbit.consensus.voting as voting
import orbit.consensus.finality as finality

proc evaluate_candidate(votes, registry, block_hash, height):
    # 1. validate each vote; invalid votes are discarded AND reported so the
    #    caller can apply trust penalties deterministically.
    let valid_votes = []
    let invalid_addrs = []
    var seen_addr = {}
    for v in votes:
        let vr = voting.validate(v, registry)
        if not vr[0]:
            push(invalid_addrs, [v.validator_addr, vr[1]])
            continue
        let key = v.validator_addr + "|" + v.block_hash
        if dict_has(seen_addr, key):
            push(invalid_addrs, [v.validator_addr, "duplicate_vote"])
            continue
        seen_addr[key] = true
        push(valid_votes, v)

    # 2. weighted tally restricted to votes for THIS candidate at THIS height
    let t = voting.tally(valid_votes, registry, block_hash, height)

    # 3. threshold -> certificate or nil
    var cert = nil
    if finality.meets_threshold(t["yes"], t["total"]):
        cert = finality.from_tally(height, block_hash, t, len(valid_votes))
    return {"certificate": cert, "tally": t, "invalid": invalid_addrs}
