# SageChain — Orbit Blockchain

Deterministic, lightweight blockchain built in SageLang. Implements the [Orbit plan](./plan.md) — ORBIT token (100B supply, 10⁸ base units), dynamic Proof-of-Time mining, Proof of Insight (PoI) validator consensus, and a Sage-native importable API.

```
import orbit
import orbit.core.chain
import orbit.wallet.account
```

## Quick start (sage-c)

```sh
sage-c tests/run_tests.sh   # 16 suites / 230 checks
sage-c -c 'import orbit; print("orbit loaded")'
```

## Layout

```
orbit/           chain packages (core, crypto, consensus, mining, wallet, network, storage, contracts, api, cli, devnet, ecosystem)
tests/           unit + vectors + run_tests.sh
docs/            protocol documentation (ORBIT.md, MINING.md, CONSENSUS.md, etc.)
tools/           gen_mining_vectors.sage
plan.md          full specification (54 sections)
```

See [plan.md](./plan.md) §52 for the dependency-order build plan and §53 for the first deliverable (single-node genesis → block → state root).

## Status

**Phase 1–10 complete** — Deterministic core, mining, PoI consensus, P2P gossip/sync, wallet CLI, RPC API, 3-node devnet, lockups, ecosystem clients, and smart contracts all implemented and tested under `sage-c`.

- **Phase 1**: Deterministic core (canonical serialization, bigint, transactions, merkle state, genesis, block validation)
- **Phase 2**: Wallets & token transfer (Lamport keypairs, orb addresses, signing, nonces, fees)
- **Phase 3**: Mining (UserFactor, SupplyFactor, TimeDecay, NodeBoost, fixed-point math, reward issuance, test vectors)
- **Phase 4**: PoI consensus (validator registry, trust/uptime scoring, signed weighted voting, 2/3 finality, no-reorg rule)
- **Phase 5**: P2P transport/sync (peer identity, handshake, gossip rules, rate limits, chain sync, block/transaction gossip)
- **Phase 6**: Devnet (3-node deterministic network, mining rewards, transfers, disconnect/reconnect, state convergence, finality)
- **Phase 7**: Explorer/API (HTTP server, RPC endpoints, explorer queries for blocks/txs/addresses/validators/mining/network)
- **Phase 8**: Token lockups (lock/unlock/claim transactions, deterministic 5% APR rewards, state machine)
- **Phase 9**: Ecosystem clients (Discord bot, web wallet, exchange client with order matching, API documentation)
- **Phase 10**: Smart contracts (Orbim VM, gas accounting, WASM sandbox, contract deploy/call, deterministic state roots)

## Test suites

```
t01  encoding              (14 checks)  canonical serialization
t02  bigint                (16 checks)  arbitrary-precision arithmetic
t03  signature/address     (12 checks)  Lamport sigs, orb address derivation
t04  transaction/ledger    (11 checks)  transfer validation, nonce, fees, ledger apply
t05  state/merkle          (8 checks)   deterministic state roots, merkle proofs
t06  genesis/chain         (17 checks)  genesis construction, chain initialization
t07  mining                (16 checks)  dynamic rate factors, reward calculation, edge cases
t08  determinism           (4 checks)   cross-node byte-for-byte identical state
t09  validator/trust        (14 checks)  validator registry, trust/uptime scoring
t10  voting/finality        (18 checks)  PoI weighted voting, 2/3 threshold, certificates
t11  p2p/gossip             (7 checks)   duplicate rejection, size limits, network隔离, rate limiting
t12  sync                   (10 checks)  chain synchronization, block ingestion
t13  devnet                 (14 checks)  3-node integration: mining, transfers, finality, convergence
t14  lockup                 (30 checks)  lock/unlock/claim, APR rewards, state machine
t15  ecosystem              (30 checks)  Discord bot, web wallet, exchange client
t16  contract               (14 checks)  contract deploy/call, gas, VM, state roots
```

## Address format

`orb` + 40 hex chars (43 total), e.g. `orb6c7cefb46b16de8a445108cb6f592f1823bfb468`.
Derived as `orb` + sha256(canonical(Lamport public key))[:40].

## Signatures (devnet)

Lamport one-time over SHA-256 — publicly verifiable. One keypair per transaction in this scheme; ed25519 replaces it before testnet (plan §24).

## CLI (orbin)

```sh
orbin wallet create <name> <seed> [password]
orbin wallet list [password]
orbin wallet address <name> [password]
orbin wallet balance <name> <chain_json> [password]
orbin wallet send <name> <recipient> <amount> <fee> <nonce> <timestamp> [memo] [password]
orbin wallet sign <name> <data_json> [password]
orbin wallet verify <pubkey_json> <data_json> <sig_json>
```

## RPC API (local)

```
GET  /status           node status (height, tip, finalized, pool)
GET  /network          network info
GET  /blocks/latest    latest block
GET  /blocks/<height>  block by height
GET  /blocks/hash/<hash>  block by hash
GET  /tx/<txid>        transaction by ID
GET  /address/<addr>   account state
GET  /validators       validator list
GET  /validators/<id>  validator detail
GET  /mining/rate      current mining rate
GET  /supply           supply info
POST /tx               submit transaction
```

## Explorer Endpoints

```
GET  /explorer/blocks?page=0&limit=20      paginated blocks (newest first)
GET  /explorer/txs?page=0&limit=50         paginated transactions
GET  /explorer/address/<address>           address with recent transactions
GET  /explorer/validators                  all validators with full details
GET  /explorer/mining/stats                current rate, pool, recent rewards
GET  /explorer/network/health              height, finality lag, validator count
```

## Smart Contract Endpoints

```
GET  /tx/<txid>        contract deployment/call transactions
GET  /explorer/address/<contract>  contract state (balance, nonce, storage)
```

## Protocol documents

See [docs/](./docs/) for detailed specifications:
- [ORBIT.md](./docs/ORBIT.md) — Technical protocol overview
- [MINING.md](./docs/MINING.md) — Canonical mining-rate formula, fixed-point implementation, reward issuance, test vectors
- [CONSENSUS.md](./docs/CONSENSUS.md) — PoI, validator scoring, proposals, voting, finality
- [NETWORK.md](./docs/NETWORK.md) — P2P protocol, peer identity, synchronization, message formats
- [SECURITY.md](./docs/SECURITY.md) — Threat model and security assumptions
- [TOKENOMICS.md](./docs/TOKENOMICS.md) — Supply allocations, lockups, mining pool, emissions
- [ORBIT_RPC.md](./docs/ORBIT_RPC.md) — Public API and client protocol
- [API.md](./docs/API.md) — Complete REST API reference

## License

MIT — see [LICENSE](./LICENSE)