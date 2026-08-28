# orbit/crypto/hash.sage — narrow hash interface (§24)
# Orbit Blockchain | Protocol v1 | Status: skeleton


# Backed by SageLang crypto.hash (SHA-256 family). Algorithm is pinned in
# the genesis protocol config; application code must not bypass this API.

import crypto.hash

proc hash(data):
    return crypto.hash.sha256(data)
