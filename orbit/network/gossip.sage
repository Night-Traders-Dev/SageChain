# orbit/network/gossip.sage — gossip rules + rate limits (§25)
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.network.protocol as proto

let MAX_MSG_SIZE = 65536
let RATE_LIMIT_PER_WINDOW = 100
let RATE_WINDOW_BLOCKS = 10
let MAX_SEEN_CACHE = 1000

class GossipNode:
    proc init(self, peer_mgr):
        self.peer_mgr = peer_mgr
        self.seen_ids = {}
        self.seen_order = []
        self.inbox = []      # [{msg, from_id}] for sync to pull
        self.outbox = []     # outbound broadcast queue (test harness reads it)

    proc _is_duplicate(self, msg_id):
        return dict_has(self.seen_ids, msg_id)

    proc _remember(self, msg_id):
        self.seen_ids[msg_id] = true
        push(self.seen_order, msg_id)
        if len(self.seen_order) > MAX_SEEN_CACHE:
            let oldest = self.seen_order[0]
            self.seen_order = slice(self.seen_order, 1, len(self.seen_order))
            dict_delete(self.seen_ids, oldest)

    proc _rate_check(self, sender_id, height):
        let p = self.peer_mgr.get(sender_id)
        if p == nil:
            return [false, "unknown_peer"]
        # window rollover
        if p.rate_window != height:
            p.rate_window = height
            p.rate_count = 0
        if p.rate_count >= RATE_LIMIT_PER_WINDOW:
            return [false, "rate_limited"]
        p.rate_count = p.rate_count + 1
        return [true, nil]

    proc receive(self, msg, height):
        # size cap
        import orbit.crypto.encoding as encoding
        if len(encoding.encode_canonical(msg.canonical_dict())) > MAX_MSG_SIZE:
            return [false, "oversize"]
        if self._is_duplicate(msg.msg_id):
            return [false, "duplicate"]
        let vr = proto.verify_message(msg, self.peer_mgr.network_id)
        if not vr[0]:
            return vr
        let rc = self._rate_check(msg.sender_id, height)
        if not rc[0]:
            return rc
        self._remember(msg.msg_id)
        push(self.inbox, {"msg": msg, "from": msg.sender_id})
        return [true, nil]

    proc broadcast(self, msg):
        # local broadcast: remember + enqueue for each peer (test harness fans out)
        if msg.msg_id == nil:
            msg.compute_id()
        self._remember(msg.msg_id)
        push(self.outbox, msg)
        return true