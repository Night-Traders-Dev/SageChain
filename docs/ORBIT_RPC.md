# ORBIT_RPC — Public API

Status: draft (Phase 7)

## Endpoints (§31)

    GET  /status            GET  /network
    GET  /blocks/latest     GET  /blocks/<height>
    GET  /blocks/hash/<hash>
    GET  /tx/<txid>         GET  /address/<address>
    GET  /validators        GET  /validators/<id>
    GET  /mining/rate       GET  /supply
    POST /tx

Secret-handling rule: the node API NEVER exposes private keys or local
wallet secrets (§31).

Clients: explorer (§32), Discord bot (§34 — RPC client only), web wallet,
exchange interface (§33 — settles through signed transactions; can never
rewrite chain state directly).
