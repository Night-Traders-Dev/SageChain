# orbit/network/protocol.sage — wire message formats (§25)
# Orbit Blockchain | Protocol v1 | Status: implemented
#
# Envelope: protocol_version message_type network_id sender_id
#           sequence payload signature

import orbit.crypto.encoding as encoding
from crypto.hash import sha256_hex

let PROTOCOL_VERSION = 1

let MSG_HELLO          = "HELLO"
let MSG_PEER_LIST      = "PEER_LIST"
let MSG_GET_BLOCK      = "GET_BLOCK"
let MSG_BLOCK          = "BLOCK"
let MSG_GET_BLOCKS     = "GET_BLOCKS"
let MSG_BLOCKS         = "BLOCKS"
let MSG_GET_TX         = "GET_TX"
let MSG_TX             = "TX"
let MSG_VOTE           = "VOTE"
let MSG_PROPOSAL       = "PROPOSAL"
let MSG_FINALITY       = "FINALITY"
let MSG_STATE_REQUEST  = "STATE_REQUEST"
let MSG_STATE_RESPONSE = "STATE_RESPONSE"
let MSG_PING           = "PING"
let MSG_PONG           = "PONG"

class Message:
    proc init(self, msg_type, network_id, sender_id, sequence, payload):
        self.protocol_version = PROTOCOL_VERSION
        self.message_type = msg_type
        self.network_id = network_id
        self.sender_id = sender_id
        self.sequence = sequence
        self.payload = payload
        self.signature = nil
        self.msg_id = nil
        self._pubkey = nil

    proc canonical_dict(self):
        return {
            "protocol_version": self.protocol_version,
            "message_type": self.message_type,
            "network_id": self.network_id,
            "sender_id": self.sender_id,
            "sequence": self.sequence,
            "payload": self.payload,
        }

    proc compute_id(self):
        self.msg_id = sha256_hex(encoding.encode_canonical(self.canonical_dict()))
        return self.msg_id

    proc sign(self, seed):
        import orbit.wallet.account as account
        import orbit.crypto.signatures as sig
        # sign canonical envelope; store Lamport sig array
        self.signature = sig.sign(seed, encoding.encode_canonical(self.canonical_dict()))
        # expose public key for verification (carried alongside)
        self._pubkey = account.derive_public_key(seed)
        self.compute_id()
        return self

proc verify_message(msg, expected_network):
    if msg.protocol_version != PROTOCOL_VERSION:
        return [false, "bad_version"]
    if msg.network_id != expected_network:
        return [false, "bad_network"]
    if msg.signature == nil or msg._pubkey == nil:
        return [false, "missing_signature"]
    import orbit.crypto.signatures as sig
    import orbit.wallet.account as account
    if not sig.verify(msg._pubkey, encoding.encode_canonical(msg.canonical_dict()), msg.signature):
        return [false, "bad_signature"]
    if account.derive_address_from_public_key(msg._pubkey) != msg.sender_id:
        return [false, "sender_mismatch"]
    return [true, nil]