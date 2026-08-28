# t11 — P2P gossip rules (§25)
import orbit.network.peer as peermod
import orbit.network.protocol as proto
import orbit.network.gossip as gossipmod
import orbit.wallet.account as account

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

let net = "orbit-devnet"
let pm = peermod.PeerManager("local", net)
let alice = account.generate_keypair("p2p-alice-seed")
let bob = account.generate_keypair("p2p-bob-seed")
pm.add_peer(peermod.Peer(alice["address"], alice["address"], net))
pm.add_peer(peermod.Peer(bob["address"], bob["address"], net))
let gossip = gossipmod.GossipNode(pm)

proc mk_msg(sender_seed, payload):
    let m = proto.Message(proto.MSG_TX, net, account.derive_address(sender_seed), 1, payload)
    m.sign(sender_seed)
    return m

let m1 = mk_msg("p2p-alice-seed", {"tx": "a"})
check("first-delivery", gossip.receive(m1, 5)[0])
check("duplicate-rejected", not gossip.receive(m1, 5)[0])

let m_bad_net = proto.Message(proto.MSG_TX, "other-net", alice["address"], 2, {"tx": "b"})
m_bad_net.sign("p2p-alice-seed")
check("bad-network-rejected", not gossip.receive(m_bad_net, 5)[0])

# oversize: craft a huge payload string
let huge = "x"
var i = 0
while i < 16:
    huge = huge + huge
    i = i + 1
let m_huge = proto.Message(proto.MSG_TX, net, alice["address"], 3, {"blob": huge})
m_huge.sign("p2p-alice-seed")
check("oversize-rejected", not gossip.receive(m_huge, 5)[0])

# rate limit: 100 allowed per window, 101st rejected; next window resets
let pm2 = peermod.PeerManager("local2", net)
pm2.add_peer(peermod.Peer(alice["address"], alice["address"], net))
let g2 = gossipmod.GossipNode(pm2)
var rate_ok = true
i = 0
while i < 100:
    let m = proto.Message(proto.MSG_PING, net, alice["address"], 10 + i, {"i": i})
    m.sign("p2p-alice-seed")
    if not g2.receive(m, 99)[0]:
        rate_ok = false
    i = i + 1
check("rate-limit-100-ok", rate_ok)
let over = proto.Message(proto.MSG_PING, net, alice["address"], 200, {"i": 999})
over.sign("p2p-alice-seed")
check("rate-limit-101-rejected", not g2.receive(over, 99)[0])
let after = proto.Message(proto.MSG_PING, net, alice["address"], 201, {"i": 1000})
after.sign("p2p-alice-seed")
check("rate-limit-reset-next-window", g2.receive(after, 100)[0])

print("t11 p2p/gossip: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t11 FAILED"