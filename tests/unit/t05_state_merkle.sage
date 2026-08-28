# t05 — world state determinism + merkle roots/proofs (plan §19, §22)
import orbit.core.state as statemod
import orbit.core.merkle as merkle
from crypto.hash import sha256_hex

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

let a = statemod.WorldState()
a.get("orbaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")["balance"] = "100"
a.get("orbccccccccccccccccccccccccccccccccccccccc")["balance"] = "300"
a.get("orbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")["balance"] = "200"

# insertion order must not matter (§21)
let b = statemod.WorldState()
b.get("orbccccccccccccccccccccccccccccccccccccccc")["balance"] = "300"
b.get("orbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")["balance"] = "200"
b.get("orbaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")["balance"] = "100"

check("root-order-free", a.state_root() == b.state_root())

let before = a.state_root()
a.get("orbaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")["balance"] = "101"
check("root-sensitive", a.state_root() != before)
check("root-empty-nonnil", statemod.WorldState().state_root() != nil)

# clone isolation
let c1 = statemod.WorldState()
c1.get("orbddddddddddddddddddddddddddddddddddddddddd")["balance"] = "5"
let snapshot_root = c1.state_root()
let c2 = c1.clone()
c2.get("orbddddddddddddddddddddddddddddddddddddddddd")["balance"] = "999"
check("clone-isolated", c1.state_root() == snapshot_root and c2.state_root() != snapshot_root)

# merkle: root, order sensitivity, proof verify
let leaves = [sha256_hex("A"), sha256_hex("B"), sha256_hex("C"), sha256_hex("D")]
let r4 = merkle.root(leaves)
check("merkle-deterministic", r4 == merkle.root([sha256_hex("A"), sha256_hex("B"), sha256_hex("C"), sha256_hex("D")]))
check("merkle-order-sensitive", r4 != merkle.root([sha256_hex("D"), sha256_hex("B"), sha256_hex("C"), sha256_hex("A")]))

var all_proofs_ok = true
for i in range(4):
    let p = merkle.proof(leaves, i)
    if not merkle.verify(r4, leaves[i], p):
        all_proofs_ok = false
check("merkle-proofs-verify", all_proofs_ok)

let odd_leaves = [sha256_hex("X"), sha256_hex("Y"), sha256_hex("Z")]
let podd = merkle.proof(odd_leaves, 2)   # duplicated-self leaf
check("merkle-odd-proof", merkle.verify(merkle.root(odd_leaves), odd_leaves[2], podd))

print("t05 state/merkle: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t05 FAILED"
