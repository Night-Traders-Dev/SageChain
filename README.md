# SageChain — Orbit Blockchain

Deterministic, lightweight blockchain built in SageLang. Implements the [Orbit plan](./plan.md) — ORBIT token (100B supply, 10⁸ base units), dynamic Proof-of-Time mining, Proof of Insight (PoI) validator consensus, and a Sage-native importable API.

```
import orbit
import orbit.core.chain
import orbit.wallet.account
```

## Quick start (sage-c)

```sh
sage-c tests/run_tests.sh   # 10 suites / 142 checks
sage-c -c 'import orbit; print("orbit loaded")'
```

## Layout

```
orbit/           chain packages (core, crypto, consensus, mining, wallet, network, storage, contracts, api, cli)
tests/           unit + vectors + run_tests.sh
tools/           gen_mining_vectors.sage
plan.md          full specification (52 sections)
```

See [plan.md](./plan.md) §52 for the dependency-order build plan and §53 for the first deliverable (single-node genesis → block → state root).

## Status

Phase 1 (deterministic core) + Phase 4 (PoI consensus) implemented and tested under `sage-c`.
Next: P2P transport/sync, wallet CLI, RPC/explorer.

## Address format

`orb` + 40 hex chars (43 total), e.g. `orb6c7cefb46b16de8a445108cb6f592f1823bfb468`.
Derived as `orb` + sha256(canonical(Lamport public key))[:40].

## Signatures (devnet)

Lamport one-time over SHA-256 — publicly verifiable. One keypair per transaction in this scheme; ed25519 replaces it before testnet (plan §24).

## License

MIT — see [LICENSE](./LICENSE)
```
