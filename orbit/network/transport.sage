# orbit/network/transport.sage — network transport abstraction
# Orbit Blockchain | Protocol v1 | Status: implemented (abstraction)

import orbit.network.protocol as proto
import orbit.network.peer as peermod
import orbit.network.gossip as gossipmod
import orbit.network.sync as syncmod

# Transport interface (to be implemented by concrete transport)
class Transport:
    proc init(self, local_id, network_id):
        self.local_id = local_id
        self.network_id = network_id
        self.peers = peermod.PeerManager(local_id, network_id)
        self.gossip = gossipmod.GossipNode(self.peers)
        self.sync = syncmod.SyncManager(nil, self.peers)  # chain set later

    proc start(self):
        return true

    proc stop(self):
        return true

    proc connect(self, addr):
        return false

    proc disconnect(self, peer_id):
        return true

    proc send(self, peer_id, message):
        return false

    proc broadcast(self, message):
        return false

    proc on_message(self, peer_id, message):
        return self.handle_incoming(peer_id, message)

    proc handle_incoming(self, peer_id, message):
        let envelope = {"msg": message, "from": peer_id}
        return self.sync.handle_message(envelope)

    proc set_chain(self, chain):
        self.sync = syncmod.SyncManager(chain, self.peers)

# In-memory transport (for testing / single-node)
class MemoryTransport:
    proc init(self, local_id, network_id):
        self.transport = Transport(local_id, network_id)
        self.connected_transports = {}  # peer_id -> MemoryTransport

    proc start(self):
        return true

    proc stop(self):
        return true

    proc connect(self, other_transport):
        let peer_id = other_transport.transport.local_id
        self.transport.peers.add_peer(peermod.Peer(peer_id, peer_id, self.transport.network_id))
        other_transport.transport.peers.add_peer(peermod.Peer(self.transport.local_id, self.transport.local_id, self.transport.network_id))
        self.connected_transports[peer_id] = other_transport
        other_transport.connected_transports[self.transport.local_id] = self
        return true

    proc send(self, peer_id, message):
        if peer_id in self.connected_transports:
            return self.connected_transports[peer_id].transport.on_message(self.transport.local_id, message)
        return false

    proc broadcast(self, message):
        for peer_id in self.connected_transports:
            self.send(peer_id, message)
        return true

    proc set_chain(self, chain):
        self.transport.set_chain(chain)

# TCP transport placeholder (needs actual socket implementation)
class TCPTransport:
    proc init(self, local_id, network_id, listen_addr):
        self.transport = Transport(local_id, network_id)
        self.listen_addr = listen_addr
        self.socket = nil
        self.running = false

    proc start(self):
        # Would bind to listen_addr and accept connections
        self.running = true
        return true

    proc stop(self):
        self.running = false
        return true

    proc connect(self, addr):
        # Would dial TCP address
        return false

    proc send(self, peer_id, message):
        return false

    proc broadcast(self, message):
        return false

# Transport factory
proc create_transport(type, local_id, network_id, config):
    if type == "memory":
        return MemoryTransport(local_id, network_id)
    elif type == "tcp":
        let addr = config["listen_addr"] or "0.0.0.0:8333"
        return TCPTransport(local_id, network_id, addr)
    else:
        return nil