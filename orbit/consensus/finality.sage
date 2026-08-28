# orbit/consensus/finality.sage — certificates + immutability (plan §27)
# Orbit Blockchain | Protocol v1 | Status: implemented (v1 threshold)
#
# Finality threshold: 2/3 of tallied weight, integer-pinned as
#     3 * yes_weight >= 2 * total_weight
# (no division — exact at every boundary, e.g. total=3 requires yes>=2).

let FINALITY_NUM = 3   # multiplies yes_weight
let FINALITY_DEN = 2   # multiplies total_weight

proc meets_threshold(yes_weight, total_weight):
    # zero-weight rounds (no active validators) never finalize
    if total_weight <= 0:
        return false
    return FINALITY_NUM * yes_weight >= FINALITY_DEN * total_weight

class FinalityCertificate:
    proc init(self, height, block_hash, yes_weight, total_weight, voter_count):
        self.height = height
        self.block_hash = block_hash
        self.yes_weight = yes_weight
        self.total_weight = total_weight
        self.voter_count = voter_count

    proc verify_integrity(self):
        if self.height < 0:
            return false
        if len(self.block_hash) != 64:
            return false
        if self.total_weight <= 0:
            return false
        return meets_threshold(self.yes_weight, self.total_weight)

# A node re-derives the certificate from stored votes; identical inputs give
# an identical certificate (§27: finality is deterministic).
proc from_tally(height, block_hash, tally_result, vote_count):
    let t = tally_result
    if not meets_threshold(t["yes"], t["total"]):
        return nil
    return FinalityCertificate(height, block_hash,
                               t["yes"], t["total"], vote_count)
