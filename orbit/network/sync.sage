# orbit/network/sync.sage — chain synchronization (§26)
# Orbit Blockchain | Protocol v1 | Status: implemented (devnet sync)
#
# Never trust longest chain blindly; PoI finality certificates decide.

import orbit.network.protocol as proto
import orbit.core.block as blockmod

class SyncManager:
    proc init(self, chain, peer_mgr):
        self.chain = chain
        self.peer_mgr = peer_mgr
        self.requested = {}   # hash -> height (dedup)

    proc handle_message(self, envelope):
        let msg = envelope["msg"]
        let peer_id = envelope["from"]
        if msg.message_type == proto.MSG_HELLO:
            # reply with our tip height
            return self._reply_peer_list(peer_id)
        if msg.message_type == proto.MSG_GET_BLOCK:
            return self._serve_block(msg.payload["hash"], peer_id)
        if msg.message_type == proto.MSG_GET_BLOCKS:
            return self._serve_range(msg.payload["from_height"], msg.payload["to_height"], peer_id)
        if msg.message_type == proto.MSG_BLOCK:
            return self._ingest_block(msg.payload["block"])
        if msg.message_type == proto.MSG_BLOCKS:
            var ok = true
            for blk in msg.payload["blocks"]:
                let r = self._ingest_block(blk)
                if not r[0]:
                    ok = false
            return [ok, nil]
        return [false, "unknown_type"]

    proc _reply_peer_list(self, peer_id):
        return [true, {"peers": self.peer_mgr.peer_list()}]

    proc _serve_block(self, h, peer_id):
        # lookup by hash via linear scan (devnet; binary index is Phase 1.1+)
        for blk in self.chain.blocks:
            if blk.hash == h:
                return [true, blk]
        return [false, "not_found"]

    proc _serve_range(self, from_h, to_h, peer_id):
        let out = []
        for blk in self.chain.blocks:
            if blk.height >= from_h and blk.height <= to_h:
                push(out, blk)
        return [true, out]

    proc _ingest_block(self, blk):
        let r = self.chain.append_block(blk)
        return r

    proc request_missing(self, peer_id, from_height, to_height):
        return proto.Message(proto.MSG_GET_BLOCKS, self.peer_mgr.network_id,
                             self.peer_mgr.local_node_id, 0,
                             {"from_height": from_height, "to_height": to_height})