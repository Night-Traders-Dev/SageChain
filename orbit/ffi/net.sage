# orbit/ffi/net.sage — TCP networking with FFI fallback
# Orbit Blockchain | Protocol v1 | Status: implemented (stubs)

import orbit.ffi.bindings as ffi
import orbit.network.protocol as proto
import orbit.network.peer as peermod

let _use_ffi = ffi.ffi_available()

# ============================================================
# TCP SERVER
# ============================================================

class TCPServer:
    proc init(self, host, port):
        self.host = host
        self.port = port
        self.socket_fd = nil
        self.running = false
        self.clients = {}  # fd -> {peer_id, addr}

    proc start(self):
        if _use_ffi:
            let result = ffi.ffi_tcp_socket()
            if not result[0]:
                return result
            self.socket_fd = result[1]

            result = ffi.ffi_tcp_bind(self.socket_fd, self.host, self.port)
            if not result[0]:
                ffi.ffi_tcp_close(self.socket_fd)
                return result

            result = ffi.ffi_tcp_listen(self.socket_fd, 128)
            if not result[0]:
                ffi.ffi_tcp_close(self.socket_fd)
                return result

            self.running = true
            return [true, nil]
        else:
            return [false, "TCP server not available (no FFI)"]

    proc stop(self):
        self.running = false
        if self.socket_fd != nil and _use_ffi:
            ffi.ffi_tcp_close(self.socket_fd)
        self.socket_fd = nil
        return [true, nil]

    proc accept(self):
        if not self.running:
            return [false, "server not running"]
        if not _use_ffi:
            return [false, "not available (no FFI)"]

        let result = ffi.ffi_tcp_accept(self.socket_fd)
        if not result[0]:
            return result

        let client_fd = result[1]
        let peer_result = ffi.ffi_tcp_get_peer_addr(client_fd)
        let peer_addr = "unknown"
        if peer_result[0]:
            peer_addr = peer_result[1]

        let peer_id = "peer_" + str(client_fd)
        self.clients[client_fd] = {"peer_id": peer_id, "addr": peer_addr}
        return [true, {"fd": client_fd, "peer_id": peer_id, "addr": peer_addr}]

    proc close_client(self, fd):
        if dict_has(self.clients, fd):
            if _use_ffi:
                ffi.ffi_tcp_close(fd)
            self.clients[fd] = nil
        return [true, nil]

    proc get_clients(self):
        let out = []
        for fd in self.clients:
            push(out, self.clients[fd])
        return out

# ============================================================
# TCP CLIENT
# ============================================================

class TCPClient:
    proc init(self, host, port):
        self.host = host
        self.port = port
        self.socket_fd = nil
        self.connected = false

    proc connect(self):
        if _use_ffi:
            let result = ffi.ffi_tcp_connect(self.host, self.port)
            if not result[0]:
                return result
            self.socket_fd = result[1]
            self.connected = true
            return [true, nil]
        else:
            return [false, "TCP client not available (no FFI)"]

    proc send(self, data):
        if not self.connected:
            return [false, "not connected"]
        if _use_ffi:
            return ffi.ffi_tcp_send(self.socket_fd, data)
        else:
            return [false, "not available (no FFI)"]

    proc recv(self, max_len = 4096):
        if not self.connected:
            return [false, "not connected"]
        if _use_ffi:
            return ffi.ffi_tcp_recv(self.socket_fd, max_len)
        else:
            return [false, "not available (no FFI)"]

    proc close(self):
        self.connected = false
        if self.socket_fd != nil and _use_ffi:
            ffi.ffi_tcp_close(self.socket_fd)
        self.socket_fd = nil
        return [true, nil]

# ============================================================
# HIGH-LEVEL MESSAGE TRANSPORT
# ============================================================

class MessageTransport:
    proc init(self, local_id, network_id):
        self.local_id = local_id
        self.network_id = network_id
        self.peers = peermod.PeerManager(local_id, network_id)
        self.servers = {}  # host:port -> TCPServer
        self.clients = {}  # peer_id -> TCPClient

    proc start_server(self, host, port):
        let server = TCPServer(host, port)
        let result = server.start()
        if result[0]:
            self.servers[host + ":" + str(port)] = server
        return result

    proc stop_server(self, host, port):
        let key = host + ":" + str(port)
        if dict_has(self.servers, key):
            let result = self.servers[key].stop()
            self.servers[key] = nil
            return result
        return [false, "server not found"]

    proc connect_peer(self, peer_id, host, port):
        let client = TCPClient(host, port)
        let result = client.connect()
        if result[0]:
            self.clients[peer_id] = client
            self.peers.add_peer(peermod.Peer(peer_id, peer_id, self.network_id))
        return result

    proc disconnect_peer(self, peer_id):
        if dict_has(self.clients, peer_id):
            self.clients[peer_id].close()
            self.clients[peer_id] = nil
        return [true, nil]

    proc send_message(self, peer_id, message):
        if not dict_has(self.clients, peer_id):
            return [false, "peer not connected"]
        let encoded = encode_message(message)
        return self.clients[peer_id].send(encoded)

    proc broadcast(self, message):
        let encoded = encode_message(message)
        var ok = true
        for pid in self.clients:
            let result = self.clients[pid].send(encoded)
            if not result[0]:
                ok = false
        return [ok, nil]

    proc receive_loop(self):
        # This would be called in a separate thread/task
        for key in self.servers:
            let server = self.servers[key]
            while server.running:
                let accept_result = server.accept()
                if accept_result[0]:
                    # New connection - would handle in gossip/protocol
                    pass
                ffi.ffi_sleep_ms(10)

# Message encoding
proc encode_message(msg):
    import orbit.crypto.encoding as enc
    return enc.encode_canonical(msg.canonical_dict())

proc decode_message(data):
    import orbit.crypto.encoding as enc
    let decoded = enc.decode_canonical(data)
    return proto.Message(
        decoded["message_type"],
        decoded["network_id"],
        decoded["sender_id"],
        decoded["sequence"],
        decoded["payload"]
    )

# ============================================================
# CONNECTION POOL
# ============================================================

class ConnectionPool:
    proc init(self, local_id, network_id, max_connections = 50):
        self.local_id = local_id
        self.network_id = network_id
        self.max_connections = max_connections
        self.transport = MessageTransport(local_id, network_id)
        self.connecting = {}

    proc start(self, host, port):
        return self.transport.start_server(host, port)

    proc stop(self):
        for key in self.transport.servers:
            self.transport.stop_server(key.split(":")[0], int(key.split(":")[1]))
        return [true, nil]

    proc ensure_connection(self, peer_id, host, port):
        if dict_has(self.transport.clients, peer_id):
            return [true, nil]
        if dict_has(self.connecting, peer_id):
            return [true, nil]

        if len(self.transport.clients) >= self.max_connections:
            return [false, "max connections reached"]

        self.connecting[peer_id] = true
        let result = self.transport.connect_peer(peer_id, host, port)
        self.connecting[peer_id] = nil

        if result[0]:
            return [true, nil]
        else:
            return result