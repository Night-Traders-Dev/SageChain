# orbit/core/merkle.sage — deterministic tree commitments (plan §22)
# Orbit Blockchain | Protocol v1 | Status: implemented
#
# Leaves are already-hashed hex strings. Odd trailing node is paired with
# itself (rule pinned here so every node computes identical roots).

from crypto.hash import sha256_hex

proc root(leaf_hashes):
    if len(leaf_hashes) == 0:
        return sha256_hex("")
    let level = []
    for l in leaf_hashes:
        push(level, l)
    while len(level) > 1:
        let nxt = []
        var i = 0
        while i < len(level):
            let left = level[i]
            var right = left
            if i + 1 < len(level):
                right = level[i + 1]
            push(nxt, sha256_hex(left + right))
            i = i + 2
        level = nxt
    return level[0]

# Standard proof of inclusion; verify() re-walks the same rules (§22 API).
proc proof(leaf_hashes, index):
    let proof_path = []
    let level = []
    for l in leaf_hashes:
        push(level, l)
    var idx = index
    while len(level) > 1:
        var sib = idx + 1
        var right_side = true
        if idx % 2 == 0:
            sib = idx + 1
            right_side = true
        else:
            sib = idx - 1
            right_side = false
        if sib >= len(level):
            sib = idx  # duplicated-self rule
            right_side = true
        push(proof_path, [level[sib], right_side])
        let nxt = []
        var i = 0
        while i < len(level):
            let left = level[i]
            var right = left
            if i + 1 < len(level):
                right = level[i + 1]
            push(nxt, sha256_hex(left + right))
            i = i + 2
        level = nxt
        idx = int(idx / 2)
    return proof_path

proc verify(root_value, leaf_hash, proof_path):
    var acc = leaf_hash
    for step in proof_path:
        if step[1]:
            acc = sha256_hex(acc + step[0])
        else:
            acc = sha256_hex(step[0] + acc)
    return acc == root_value
