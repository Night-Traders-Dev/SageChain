# orbit/network/peer.sage — peer identity and connection handling (§25)
# Orbit Blockchain | Protocol v1 | Status: implemented

import orbit.wallet.account as account
from crypto.hash import sha256_hex

let MAX_KNOWN_PEERS = 50

class Peer:
    proc init(self, node_id, address, network_id):
        self.node_id = node_id
        self.address = address
        self.network_id = network_id
        self.sequence = 0
        self.connected = false
        self.last_seen = 0
        self.penalty_points = 0
        self.rate_count = 0
        self.rate_window = 0

    proc bump_sequence(self):
        self.sequence = self.sequence + 1
        return self.sequence

    proc penalize(self, points):
        self.penalty_points = self.penalty_points + points
        return self.penalty_points

    proc is_banned(self):
        return self.penalty_points >= 100

class PeerManager:
    proc init(self, local_node_id, network_id):
        self.local_node_id = local_node_id
        self.network_id = network_id
        self.peers = {}
        self.banned = {}

    proc add_peer(self, peer):
        if dict_has(self.banned, peer.node_id):
            return [false, "banned"]
        if len(dict_keys(self.peers)) >= MAX_KNOWN_PEERS:
            return [false, "peer_limit"]
        self.peers[peer.node_id] = peer
        return [true, nil]

    proc get(self, node_id):
        if dict_has(self.peers, node_id):
            return self.peers[node_id]
        return nil

    proc remove(self, node_id):
        if dict_has(self.peers, node_id):
            dict_delete(self.peers, node_id)
            return true
        return false

    proc ban(self, node_id):
        self.banned[node_id] = true
        dict_delete(self.peers, node_id)

    proc peer_list(self):
        let out = []
        for nid in self.peers:
            push(out, nid)
        return out