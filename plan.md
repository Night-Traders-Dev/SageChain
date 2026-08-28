# Orbit Blockchain on Sage

## 1. Project Overview

Orbit is a lightweight blockchain implemented primarily in Sage, using Sage's runtime and type system while exposing a clean blockchain-specific module boundary.

The first release should preserve the core ideas of the existing Orbit design:

- ORBIT native token
- Dynamic Proof-of-Time mining
- Proof of Insight (PoI) validator consensus
- Trust/uptime-based node scoring
- Deterministic block and transaction validation
- Wallets and signed transactions
- JSON-compatible persistence for the prototype, with a path toward a binary database format
- Explorer/API support
- CLI node and wallet tooling
- Contract execution as a later capability
- Future bridge and naming-system support

The implementation should be Sage-first rather than a Python application merely called from Sage. Python interoperability may be used for development tooling, test harnesses, cryptography backends, or compatibility layers where a native Sage implementation is not yet available.

---

## 2. Goals

### Primary goals

1. Build a deterministic Orbit blockchain node in Sage.
2. Define a stable block, transaction, account, wallet, and validator model.
3. Implement Orbit's dynamic mining-rate model as consensus-critical deterministic code.
4. Implement Proof of Insight (PoI) block proposal and trust-weighted voting.
5. Make every consensus calculation reproducible across nodes.
6. Keep the protocol modular enough to run in local development, LAN mesh, and eventually public P2P networks.
7. Provide a Sage-native API that other Sage programs can import.

### Secondary goals

- Provide a CLI named `orbin` or `orbit`.
- Provide a local HTTP/JSON API for explorers and applications.
- Provide a browser explorer.
- Provide a Discord integration later.
- Provide a lightweight smart-contract sandbox later.
- Support multiple storage backends without changing consensus code.

### Non-goals for the first release

- Cross-chain bridges
- Production-grade smart contracts
- Permissionless DeFi primitives
- Hardware-accelerated cryptography
- Full Byzantine production hardening
- Economic governance mechanisms that can mutate monetary parameters without a protocol upgrade

---

## 3. Architecture

```text
                         +----------------------+
                         |      Sage Program    |
                         +----------+-----------+
                                    |
                              import orbit
                                    |
              +---------------------+---------------------+
              |                     |                     |
       +------v------+       +------v------+       +------v------+
       |   Wallet    |       |   Node      |       |   Explorer  |
       | / Accounts   |       | / Consensus |       | / API       |
       +------+-------+       +------+-------+       +-------------+
              |                      |
              +----------+-----------+
                         |
                  +------v-------+
                  | Orbit Core   |
                  +--------------+
                  | Block        |
                  | Transaction  |
                  | State        |
                  | Ledger       |
                  | Mining       |
                  | PoI          |
                  | Validation   |
                  | Crypto       |
                  +------+-------+
                         |
          +--------------+---------------+
          |                              |
   +------v------+                 +-----v------+
   | SageNet P2P |                 | SageStorage |
   | Transport   |                 | State/DB    |
   +-------------+                 +------------+
```

### Module layout

```text
orbit/
├── core/
│   ├── block.sage
│   ├── transaction.sage
│   ├── header.sage
│   ├── state.sage
│   ├── ledger.sage
│   ├── genesis.sage
│   └── errors.sage
│
├── crypto/
│   ├── hash.sage
│   ├── keys.sage
│   ├── signatures.sage
│   └── encoding.sage
│
├── consensus/
│   ├── poi.sage
│   ├── validator.sage
│   ├── voting.sage
│   ├── trust.sage
│   └── finality.sage
│
├── mining/
│   ├── rate.sage
│   ├── proof_of_time.sage
│   └── rewards.sage
│
├── wallet/
│   ├── wallet.sage
│   ├── account.sage
│   └── keystore.sage
│
├── network/
│   ├── peer.sage
│   ├── protocol.sage
│   ├── gossip.sage
│   └── sync.sage
│
├── storage/
│   ├── interface.sage
│   ├── json_store.sage
│   └── block_store.sage
│
├── contracts/
│   ├── runtime.sage
│   ├── sandbox.sage
│   └── gas.sage
│
├── api/
│   ├── rpc.sage
│   └── explorer.sage
│
└── cli/
    └── orbin.sage
```

The exact directory names may be adapted to Sage's existing project conventions.

---

## 4. Sage Integration Strategy

The current public SageTree repository demonstrates Sage's gradual typing, `struct`, `impl`, enums, pattern matching, modules/imports, manual-memory support, and both interpreter/AOT execution paths. Orbit should use those language features rather than introducing a Python-shaped abstraction layer.

Recommended Sage style:

```sage
struct Transaction:
    tx_id: str
    sender: str
    recipient: str
    amount: uint64
    fee: uint64
    nonce: uint64
    timestamp: uint64
    signature: bytes

impl Transaction:
    proc hash(self) -> str:
        return crypto.hash(self.canonical_bytes())
```

Consensus-critical structures should use explicit types wherever practical. Avoid untyped maps for values that influence consensus.

Use enums for protocol states:

```sage
enum TxKind:
    transfer
    reward
    lock
    unlock
    stake
    contract
```

Use immutable/canonical serialization for anything hashed or signed.

---

## 5. Consensus-Critical Rules

Everything that can affect whether two honest nodes accept the same chain must be deterministic.

Consensus-critical inputs include:

- Genesis configuration
- Block header fields
- Transaction serialization
- Account state
- Nonces
- Fees
- Block height
- Active-user count definition
- Remaining mining supply
- Validator/node score
- Mining-rate parameters
- Reward calculation
- PoI vote weights
- Finalization threshold
- Chain-selection/finality rules

Do not read wall-clock time directly inside a consensus calculation unless the protocol defines exactly how that time is represented and validated.

For mining, elapsed time should be represented by explicit protocol timestamps and/or accumulated eligible mining intervals, not by trusting the local operating-system clock.

---

## 6. Orbit Monetary Policy

### Total supply

```text
TOTAL_SUPPLY = 100,000,000,000 ORBIT
```

### Genesis allocations

| Wallet | Allocation | % |
|---|---:|---:|
| system | 81,900,000,000 | 81.90% |
| lockup_rewards | 100,000,000 | 0.10% |
| mining | 1,000,000,000 | 1.00% |
| nodefeecollector | 0 | 0.00% |
| community | 3,000,000,000 | 3.00% |
| team | 5,000,000,000 | 5.00% |
| airdrop | 1,000,000,000 | 1.00% |
| foundation | 2,000,000,000 | 2.00% |
| partnerships | 1,000,000,000 | 1.00% |
| reserve | 5,000,000,000 | 5.00% |

Sum must equal exactly `TOTAL_SUPPLY` at genesis.

### Fixed-point representation

Do not use binary floating-point arithmetic for balances or consensus calculations.

Recommended representation:

```text
1 ORBIT = 10^8 base units
```

Therefore:

```text
ORBIT = integer base units
1 ORBIT = 100,000,000 orbit-units
```

Mining-rate calculations may use high-precision decimal/fixed-point arithmetic internally and must be converted to integer reward units using a specified deterministic rounding rule.

Recommended rule:

```text
floor() toward zero after all consensus factors have been multiplied
```

The rounding mode must be protocol-defined and tested.

---

## 7. Dynamic Mining Model

### 7.1 Canonical formula

The intended mining behavior is:

```text
R_current = R_base × UserFactor × SupplyFactor × TimeDecay × NodeBoost
```

Use the following canonical definitions:

```text
UserFactor = (U_target / max(U, U_target))^0.5

SupplyFactor = S / S_max

TimeDecay = 0.5^(B / B_halflife)

NodeBoost = 1 + min(Score, 0.10)
```

### Important specification correction

The original specification contains two contradictory definitions for `SupplyFactor`:

```text
1 - (S / S_max)
```

and

```text
S / S_max
```

The first expression increases the reward as the mining reserve is depleted, which conflicts with the stated goal of tapering rewards. The supplied numerical examples also correspond to `S / S_max` rather than `1 - S / S_max`.

Therefore Orbit v1 MUST use:

```text
SupplyFactor = S / S_max
```

where `S` is the **remaining** mining allocation.

At full supply:

```text
S = S_max
SupplyFactor = 1
```

At zero supply:

```text
S = 0
SupplyFactor = 0
```

This rule should be written into the genesis protocol configuration and treated as consensus-critical.

---

## 8. Mining Parameters

Initial protocol parameters:

```text
R_base       = 0.082 ORBIT/sec
U_target     = 10,000 active users
S_max        = 1,000,000,000 ORBIT
B_halflife   = 100,000 blocks
NodeBoostMax = 0.10
```

Represent parameters in a machine-readable protocol configuration:

```text
orbit_protocol_version = 1
r_base = 0.082
u_target = 10000
s_max = 1000000000
b_halflife = 100000
node_boost_max = 0.10
```

Protocol versioning prevents later software changes from silently modifying historical blocks.

---

## 9. Active User Count

`U` must be defined precisely. Do not use a node-local guess.

Recommended v1 definition:

```text
U = number of unique accounts that satisfy the active-account rule
```

Define an active window such as:

```text
ACTIVE_WINDOW = N blocks
```

An account is active if it has performed at least one qualifying protocol action during that window.

Qualifying activity should exclude passive balance checks and repeated internal node messages.

The state commitment for active users must be reproducible. Recommended approach:

- Maintain an `activity_epoch`.
- Record qualifying account activity in state.
- Maintain a deterministic active-account count.
- Include the resulting state commitment in the block.

Changing the active-user definition requires a protocol-version change.

---

## 10. Remaining Mining Supply

The mining pool begins at:

```text
1,000,000,000 ORBIT
```

A reward transaction may not spend more than the remaining mining pool.

At every block:

```text
remaining = previous_remaining - rewards_minted
```

with the invariant:

```text
0 <= remaining <= S_max
```

When the calculated reward exceeds the remaining pool:

```text
reward = remaining
```

Then the mining pool is exhausted.

No other transaction type may mint from the mining pool.

---

## 11. Time Decay

Use block height rather than local time as the decay index:

```text
TimeDecay = 0.5^(B / B_halflife)
```

At exactly one half-life:

```text
B = B_halflife
TimeDecay = 0.5
```

At two half-lives:

```text
B = 2 * B_halflife
TimeDecay = 0.25
```

Do not calculate this using implementation-dependent floating-point exponentiation in final consensus code.

Possible implementation strategies:

1. High-precision deterministic fixed-point exponentiation.
2. A precomputed deterministic table with interpolation rules.
3. A rational/exponential approximation with fully specified integer arithmetic.

For v1, isolate the math behind:

```sage
mining.time_decay(block_height, half_life)
```

so the implementation can be upgraded without changing the rest of the protocol.

---

## 12. Node Score

`Score` is defined as a normalized value:

```text
0.00 <= Score <= 1.00
```

Suggested inputs:

```text
uptime
valid_block_votes
valid_transactions_seen
successful_syncs
peer_reliability
misbehavior_penalties
```

Do not allow a node to directly report its own score.

The score must be derived from observable protocol behavior.

Recommended v1 model:

```text
Score = weighted normalized validator performance metrics
```

Then:

```text
NodeBoost = 1 + min(Score, 0.10)
```

This means the maximum multiplier is:

```text
1.10
```

### Anti-gaming rules

- New validators receive a bounded initial score.
- Score changes gradually.
- Short bursts of activity must not create a large score jump.
- Persistent invalid behavior causes penalties.
- Sybil-created identities do not automatically create independent high-trust validators.

---

## 13. Mining Rate API

Create a pure function:

```sage
proc calculate_mining_rate(
    users: uint64,
    remaining_supply: uint64,
    block_height: uint64,
    node_score: decimal
) -> decimal:
    ...
```

The function must:

1. Validate inputs.
2. Clamp or reject invalid values deterministically.
3. Calculate each factor.
4. Multiply factors in a fixed order.
5. Apply deterministic rounding.
6. Return the protocol-defined value.

Also create:

```sage
proc calculate_block_reward(
    mining_rate: decimal,
    eligible_seconds: uint64,
    remaining_supply: uint64
) -> uint64:
    ...
```

The second function converts the rate into integer token units.

---

## 14. Proof of Time

Orbit mining is not intended to be energy-intensive proof-of-work.

### Model

A miner/validator accrues eligible mining time subject to protocol rules.

Suggested flow:

```text
Node joins network
        |
        v
Node establishes synchronized protocol state
        |
        v
Node enters mining eligibility window
        |
        v
Eligible time accumulates
        |
        v
Current dynamic mining rate is calculated
        |
        v
Reward is generated into a reward transaction
        |
        v
Reward transaction is included in a valid block
```

### Anti-cheating requirements

The node must not be able to manufacture arbitrary elapsed time by changing its local clock.

Use:

- network-observed block intervals
- signed protocol timestamps
- bounded timestamp drift
- monotonic local timers only for provisional behavior
- canonical chain timestamps for final accounting

The reward must be derived from data other validators can verify.

---

## 15. Proof of Insight Consensus

PoI is the Orbit consensus layer for determining whether proposed blocks are accepted.

### Participants

- proposer
- validator
- voter
- observer/full node

### Proposal flow

```text
Validator selected as proposer
          |
          v
Build candidate block
          |
          v
Broadcast proposal
          |
          v
Validators independently validate
          |
          v
Validators cast signed votes
          |
          v
Votes weighted by protocol-defined PoI weight
          |
          v
Finality threshold reached
          |
          v
Block finalized
```

### Vote weight

Define a deterministic weight function, for example:

```text
VoteWeight = BaseStakeWeight × TrustWeight × UptimeWeight
```

The exact formula must be fixed before mainnet deployment and encoded in the protocol version.

### Important separation

Mining rewards and block-finality authority should not become the same mechanism by accident.

A node may earn mining rewards based on eligibility while its consensus voting weight is separately calculated by PoI.

---

## 16. Validator State

Each validator should have a state record containing at least:

```text
validator_id
public_key
activation_height
last_seen_height
uptime_score
trust_score
valid_vote_count
invalid_vote_count
proposed_blocks
accepted_blocks
penalty_points
current_status
```

Validator state must be deterministic and committed to chain state.

---

## 17. Transaction Model

Initial transaction types:

```text
transfer
reward
lock
unlock
stake
validator_register
validator_update
contract_deploy      # later
contract_call        # later
```

### Transfer

```text
sender
recipient
amount
fee
nonce
public_key
signature
memo
```

### Reward

```text
recipient
amount
block_height
mining_seconds
mining_rate_commitment
validator_score_commitment
```

Reward transactions must be generated by protocol rules and cannot be freely authored by users.

### Lockup

```text
owner
amount
lock_start
lock_duration
claim_until
nonce
signature
```

---

## 18. Token Lockups

Initial target:

```text
~5% APR
```

The APR must not be hard-coded as an informal promise. It must be represented as a protocol parameter with explicit accounting rules.

Rewards may be generated as `reward` transactions associated with a lockup position.

Recommended state machine:

```text
UNLOCKED
   |
   | lock
   v
LOCKED
   |
   | claim interval reached
   v
CLAIMABLE
   |
   | claim
   v
LOCKED / UNLOCKED
```

The first implementation should use a deterministic per-block or per-epoch reward calculation rather than wall-clock APR calculations.

---

## 19. Account State

Use an account-state model:

```text
address
balance
nonce
locked_balance
validator_status
activity_marker
contract_state_root
```

Global state should be committed through a deterministic state root.

The state root should be stored in the block header.

---

## 20. Block Structure

Recommended block header:

```text
version
height
previous_hash
state_root
transaction_root
validator_root
active_user_root
miner_or_proposer
block_timestamp
protocol_id
nonce_or_proof_field
block_hash
```

Recommended body:

```text
transactions[]
votes[]
proof_of_time
consensus_metadata
```

Avoid ambiguous serialization. Every field included in hashing must have exactly one canonical representation.

---

## 21. Block Hashing

Define:

```text
block_hash = HASH(canonical(header_without_hash) + canonical(body_commitments))
```

Transactions should be hashed individually and committed through a transaction tree/root.

Do not hash a language-specific object representation.

Never rely on dictionary iteration order or runtime object formatting for protocol hashes.

---

## 22. Merkle / Commitment Layer

Implement deterministic tree commitments for:

- transactions
- votes
- account state
- validator state
- active-account state

Initial API:

```sage
commitment.root(items)
commitment.proof(items, index)
commitment.verify(root, item, proof)
```

This will allow the explorer, light clients, and future contract system to verify subsets of chain data.

---

## 23. Wallets

Wallet API:

```text
create
import
export
lock
unlock
address
balance
send
sign
verify
```

Private keys must not be stored directly in the blockchain.

Keystore design should support encrypted local storage.

Example CLI:

```text
orbin wallet create
orbin wallet address
orbin wallet balance <address>
orbin wallet send <address> <amount>
orbin wallet sign <payload>
```

---

## 24. Cryptography

Orbit should expose cryptography through a narrow interface:

```sage
crypto.hash(data)
crypto.generate_keypair()
crypto.sign(private_key, data)
crypto.verify(public_key, data, signature)
```

If the existing Orbit EPC implementation is retained, implement EPC behind the same interface rather than allowing application code to depend on internal cryptographic details.

The first implementation should make the exact hash and signature algorithms explicit in protocol configuration.

Do not invent cryptographic primitives for production merely because the surrounding blockchain is experimental. Unusual cryptographic systems should be treated as replaceable modules and independently reviewed.

---

## 25. P2P Network

Create a transport-independent network layer.

### Message types

```text
HELLO
PEER_LIST
GET_BLOCK
BLOCK
GET_BLOCKS
BLOCKS
GET_TX
TX
VOTE
PROPOSAL
FINALITY
STATE_REQUEST
STATE_RESPONSE
PING
PONG
```

Every network message should contain:

```text
protocol_version
message_type
network_id
sender_id
sequence
payload
signature
```

### Gossip rules

- Reject duplicate message IDs.
- Cap message sizes.
- Rate-limit peers.
- Penalize repeated invalid messages.
- Do not allow a peer to force unbounded memory allocation.

---

## 26. Chain Synchronization

Node startup:

```text
load local state
    |
    v
verify local chain
    |
    v
connect to peers
    |
    v
exchange heights/finality
    |
    v
request missing blocks
    |
    v
validate each block
    |
    v
commit verified state
```

Do not trust the longest chain solely because it is longer. PoI finality and valid consensus certificates must be considered.

---

## 27. Chain Selection and Finality

Separate:

1. candidate chain discovery
2. block validation
3. PoI voting
4. finality
5. finalized state commitment

Once a block is finalized under the protocol's finality rule, nodes must not reorganize past it except through an explicitly defined protocol recovery mechanism.

---

## 28. Storage

### v1

Use JSON for human-readable development and interoperability.

Recommended separation:

```text
blocks/
state/
validators/
transactions/
wallets/
network/
```

### v1.1+

Add a binary/key-value backend for performance.

Storage API:

```sage
store.put_block(block)
store.get_block(hash)
store.get_block_by_height(height)
store.put_state(key, value)
store.get_state(key)
store.commit()
```

Consensus code should depend on the interface rather than on JSON files directly.

---

## 29. Genesis Block

Create a static, deterministic genesis configuration.

Genesis must define:

- chain ID
- network ID
- protocol version
- total supply
- wallet allocations
- mining pool
- mining parameters
- initial validator set
- cryptographic algorithms
- block timing limits
- finality thresholds
- token decimals

The genesis block hash should be calculated once and hard-coded into the network configuration.

Example networks:

```text
orbit-devnet
orbit-testnet
orbit-mainnet
```

Each network gets a different genesis hash and network ID.

---

## 30. CLI / Orbin

Build a Sage-native command line application.

### Node commands

```text
orbin node init
orbin node start
orbin node stop
orbin node status
orbin node peers
orbin node sync
```

### Mining commands

```text
orbin mine start
orbin mine stop
orbin mine status
orbin mine rate
```

### Wallet commands

```text
orbin wallet create
orbin wallet list
orbin wallet address
orbin wallet balance
orbin wallet send
orbin wallet lock
orbin wallet unlock
```

### Chain commands

```text
orbin chain height
orbin chain block <height|hash>
orbin chain tx <txid>
orbin chain state
```

### Validator commands

```text
orbin validator register
orbin validator status
orbin validator score
orbin validator votes
```

---

## 31. RPC/API

Provide a local API suitable for the explorer.

Suggested endpoints:

```text
GET  /status
GET  /network
GET  /blocks/latest
GET  /blocks/<height>
GET  /blocks/hash/<hash>
GET  /tx/<txid>
GET  /address/<address>
GET  /validators
GET  /validators/<id>
GET  /mining/rate
GET  /supply
POST /tx
```

Do not expose private keys or local wallet secrets through the node API.

---

## 32. Explorer

Create an explorer after the core node is stable.

Pages:

- Network overview
- Latest blocks
- Block detail
- Transaction detail
- Address detail
- Validator list
- Validator detail
- Mining statistics
- ORBIT supply
- Mining-pool depletion
- Active-user count
- Network health

Charts should show at least:

```text
block height
active users
remaining mining supply
mining rate
validator participation
finality time
```

---

## 33. Exchange Layer

The existing Orbit concept includes an exchange component. Keep it separate from consensus.

Core exchange objects:

```text
market
order
trade
balance reservation
settlement
```

The exchange must never be able to directly rewrite chain state.

Trades should settle through signed transactions or another explicitly defined protocol transaction type.

---

## 34. Discord Interface

Implement later as a client of the RPC layer rather than as a direct blockchain implementation.

Example commands:

```text
/wallet
/balance
/send
/mining
/validator
/exchange
/block
/tx
```

The Discord bot should never store unencrypted private keys in command logs or bot messages.

---

## 35. Orbim Smart Contracts

Orbim is planned as the smart-contract language:

```text
Orbim source
   |
   v
Orbim compiler
   |
   v
WASM
   |
   v
Orbit contract sandbox
```

Smart contracts should not be implemented until the base ledger is deterministic and stable.

Contract runtime requirements:

- deterministic execution
- bounded memory
- bounded CPU/gas
- no unrestricted file access
- no unrestricted network access
- deterministic host functions
- deterministic serialization
- explicit contract state root

Sage's existing sandbox/capability model can be used as conceptual guidance for the host boundary.

---

## 36. Bridges

Bridges are post-mainnet work.

Design the base protocol so bridge deposits/withdrawals can later be represented without making bridges consensus-critical in v1.

Potential bridge architecture:

```text
Orbit Bridge Adapter
        |
        +---- Ethereum
        +---- Other chains
```

Bridge security requires independent verification, multisig/threshold mechanisms or light-client proofs, and should not be implemented as a simple trusted HTTP callback.

---

## 37. Security Model

### Threats

- Sybil validators
- fake uptime
- clock manipulation
- reward duplication
- double spending
- malformed blocks
- invalid signatures
- replayed transactions
- peer flooding
- fork attacks
- state corruption
- validator collusion
- exchange manipulation
- wallet key theft

### Required protections

- transaction nonces
- chain/network IDs in signed data
- deterministic serialization
- signature validation
- bounded timestamp drift
- validator penalties
- replay protection
- block size limits
- transaction size limits
- peer rate limiting
- state-root verification
- finality certificates
- atomic state commits

---

## 38. Invariants

These must have automated tests.

### Supply

```text
circulating_supply <= TOTAL_SUPPLY
mining_remaining >= 0
mining_remaining <= MINING_SUPPLY
```

### Balance

```text
balance >= 0
locked_balance >= 0
```

### Nonce

Transactions from the same account must use the expected next nonce.

### Block linkage

```text
block[n].previous_hash == block[n-1].hash
```

### State commitment

All nodes must independently compute the same state root.

### Reward conservation

For each block:

```text
reward_minted <= mining_pool_remaining_before_block
```

### Monetary conservation

Except for explicitly defined mint transactions:

```text
sum(inputs) + permitted_mint == sum(outputs) + fees
```

---

## 39. Mining Test Vectors

Create fixed test vectors for the mining formula.

Example vector structure:

```text
users=1000
remaining_supply=900000000
block_height=10000
score=0.90
```

The expected value must be generated by the canonical implementation and checked in as a test vector.

Repeat for:

```text
users=10000
remaining_supply=500000000
block_height=50000
score=0.80

users=50000
remaining_supply=200000000
block_height=100000
score=0.60

users=100000
remaining_supply=0
block_height=200000
score=1.00
```

Do not hard-code the approximate numbers from the proposal until the fixed-point precision and rounding rules are finalized.

---

## 40. Formula Edge Cases

Test at minimum:

```text
U = 0
U < U_target
U = U_target
U > U_target

S = 0
S = S_max
S > S_max

B = 0
B = B_halflife
B = 2 * B_halflife

Score = 0
Score = 0.10
Score = 1.00
Score < 0
Score > 1
```

Expected behavior for invalid values must be deterministic. Prefer rejecting impossible consensus state rather than silently normalizing malformed block data.

---

## 41. Test Strategy

### Unit tests

Test:

- transaction serialization
- hashing
- signatures
- address derivation
- mining factors
- reward calculations
- account updates
- nonce rules
- block validation
- validator score
- vote weighting
- finality
- state-root generation

### Integration tests

Run:

```text
1-node devnet
2-node devnet
3-node devnet
7-node validator network
```

Test synchronized block production and recovery after a node disconnects.

### Fault tests

Inject:

- invalid transactions
- conflicting votes
- malformed blocks
- bad signatures
- stale blocks
- duplicate rewards
- altered state roots
- fake timestamps
- peer spam

All honest nodes should converge on the same finalized state.

---

## 42. Property Tests

Where practical, use property-based tests for:

```text
serialize(deserialize(x)) == canonical(x)

hash(x) == hash(x)

verify(pk, sign(sk, x), x) == true

reward <= remaining_supply

SupplyFactor in [0,1]
UserFactor in (0,1]
TimeDecay in (0,1]
NodeBoost in [1,1.10]
```

---

## 43. Determinism Test

The most important blockchain-specific test is cross-node determinism.

Procedure:

1. Create identical genesis state.
2. Feed identical transactions to multiple independent nodes.
3. Process the same block sequence.
4. Compare:
   - block hashes
   - transaction roots
   - state roots
   - validator roots
   - active-user commitments
   - remaining mining supply
5. Require byte-for-byte identical consensus results.

Run this under multiple Sage execution modes where supported.

---

## 44. Development Milestones

### Phase 0 — Protocol freeze

- [ ] Freeze ORBIT decimals.
- [ ] Freeze genesis allocations.
- [ ] Freeze mining formula.
- [ ] Resolve `SupplyFactor` conflict in protocol specification.
- [ ] Define active-user semantics.
- [ ] Define node-score semantics.
- [ ] Define PoI vote-weight formula.
- [ ] Define finality threshold.
- [ ] Define cryptographic primitives.
- [ ] Define canonical serialization.

### Phase 1 — Sage Orbit core

- [ ] Create `orbit` module.
- [ ] Implement transaction structure.
- [ ] Implement block structure.
- [ ] Implement canonical encoding.
- [ ] Implement hashes.
- [ ] Implement account state.
- [ ] Implement ledger state transitions.
- [ ] Implement genesis generation.
- [ ] Implement block validation.

### Phase 2 — Wallets and token transfer

- [ ] Create keypair implementation/interface.
- [ ] Create wallet keystore.
- [ ] Create address format.
- [ ] Implement signing.
- [ ] Implement transfer transactions.
- [ ] Implement nonces.
- [ ] Implement fees.
- [ ] Add wallet CLI.

### Phase 3 — Mining

- [ ] Implement UserFactor.
- [ ] Implement SupplyFactor as `S/S_max`.
- [ ] Implement TimeDecay.
- [ ] Implement NodeBoost.
- [ ] Implement deterministic fixed-point math.
- [ ] Implement reward transactions.
- [ ] Implement remaining-mining-supply accounting.
- [ ] Add mining test vectors.

### Phase 4 — PoI consensus

- [ ] Implement validator state.
- [ ] Implement trust metrics.
- [ ] Implement uptime tracking.
- [ ] Implement vote messages.
- [ ] Implement vote signatures.
- [ ] Implement weighted voting.
- [ ] Implement block proposals.
- [ ] Implement finality certificates.

### Phase 5 — P2P

- [ ] Implement peer identity.
- [ ] Implement handshake.
- [ ] Implement block gossip.
- [ ] Implement transaction gossip.
- [ ] Implement vote gossip.
- [ ] Implement chain synchronization.
- [ ] Add peer penalties.
- [ ] Add network persistence.

### Phase 6 — Devnet

- [ ] Produce deterministic devnet genesis.
- [ ] Start three local nodes.
- [ ] Mine rewards.
- [ ] Transfer ORBIT.
- [ ] Disconnect/reconnect nodes.
- [ ] Confirm state convergence.
- [ ] Confirm finality.

### Phase 7 — Explorer/API

- [ ] Implement RPC.
- [ ] Implement explorer backend.
- [ ] Implement block pages.
- [ ] Implement transaction pages.
- [ ] Implement address pages.
- [ ] Implement validator pages.
- [ ] Implement mining charts.

### Phase 8 — Lockups

- [ ] Implement lockup transactions.
- [ ] Implement reward accounting.
- [ ] Implement claim periods.
- [ ] Add lockup tests.

### Phase 9 — Ecosystem clients

- [ ] Implement Discord client.
- [ ] Implement web wallet.
- [ ] Implement exchange client.
- [ ] Implement public API documentation.

### Phase 10 — Smart contracts

- [ ] Freeze Orbim VM ABI.
- [ ] Implement gas accounting.
- [ ] Implement deterministic WASM sandbox.
- [ ] Implement contract deployment.
- [ ] Implement contract calls.
- [ ] Commit contract state roots.

### Phase 11 — Testnet

- [ ] Public testnet genesis.
- [ ] Validator onboarding.
- [ ] Network monitoring.
- [ ] Fault-injection campaign.
- [ ] Economics simulation.
- [ ] Security review.
- [ ] Protocol documentation.

### Phase 12 — Mainnet readiness

- [ ] Freeze protocol version.
- [ ] Freeze genesis hash.
- [ ] Freeze reward parameters.
- [ ] Freeze PoI rules.
- [ ] Validate supply invariants.
- [ ] Validate finality behavior.
- [ ] Back up genesis and network configuration.
- [ ] Publish node compatibility requirements.
- [ ] Publish security/threat model.

---

## 45. Economics Simulation

Before testnet, build a standalone simulator:

```text
simulator/
├── population
├── users
├── validators
├── mining
├── blocks
├── supply
└── scenarios
```

Simulate:

- 100 users
- 1,000 users
- 10,000 users
- 50,000 users
- 100,000 users
- rapidly growing networks
- stagnant networks
- validator churn
- mining-pool depletion
- low/high node scores

Output:

```text
block_height
active_users
remaining_supply
minted_supply
mining_rate
average_reward
validator_score_distribution
```

This simulation is for economic testing and must not be used as a consensus oracle.

---

## 46. Recommended Repository Layout

```text
Orbit/
├── plan.md
├── ORBIT.md
├── MINING.md
├── TOKENOMICS.md
├── SECURITY.md
├── LICENSE
├── README.md
├── sage.mod
│
├── orbit/
│   ├── core/
│   ├── consensus/
│   ├── mining/
│   ├── crypto/
│   ├── wallet/
│   ├── network/
│   ├── storage/
│   ├── contracts/
│   ├── api/
│   └── cli/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── consensus/
│   ├── mining/
│   ├── networking/
│   └── vectors/
│
├── simulator/
├── explorer/
└── tools/
```

---

## 47. Documentation Set

Maintain these documents as protocol artifacts:

### `ORBIT.md`

Technical protocol overview.

### `MINING.md`

Canonical mining-rate formula, fixed-point implementation, reward issuance rules, and test vectors.

### `TOKENOMICS.md`

Supply allocations, lockups, mining pool, emissions, and accounting rules.

### `CONSENSUS.md`

PoI, validator scoring, proposals, voting, and finality.

### `NETWORK.md`

P2P protocol, peer identity, synchronization, and message formats.

### `SECURITY.md`

Threat model and security assumptions.

### `ORBIT_RPC.md`

Public API and client protocol.

---

## 48. Compatibility and Versioning

Every consensus-critical change must increment a protocol version when it changes historical validation behavior.

Use:

```text
major.minor
```

with the following interpretation:

```text
major = consensus-breaking change
minor = backward-compatible feature or API change
```

Blocks should carry a protocol version.

Nodes should reject unsupported consensus versions rather than silently interpreting them with the wrong rules.

---

## 49. Performance Targets

Initial targets are development targets, not guarantees:

```text
block validation: sub-second on normal desktop hardware
transaction validation: millisecond-scale
local devnet startup: <10 seconds
state reload: deterministic and bounded
```

Do not optimize before the correctness suite is stable.

Use profiling to identify:

- serialization costs
- hashing costs
- state lookup costs
- signature verification
- network gossip overhead
- consensus vote processing

Sage's manual-memory facilities may be used selectively for hot paths after profiling, while retaining normal managed memory for higher-level application code.

---

## 50. Upgrade Path

Design the protocol so later features fit without rewriting the ledger core.

Potential future modules:

```text
OrbitDNS
Orbit Bridge
Orbim Contracts
Orbit Governance
Orbit Identity
Orbit Payments
Orbit Storage
Orbit Messaging
```

Each should integrate through explicit protocol interfaces.

---

## 51. Definition of Done for Orbit v1

Orbit v1 is complete when all of the following are true:

- [ ] A node can create/load a genesis chain.
- [ ] A wallet can create keys and addresses.
- [ ] Users can submit signed transfers.
- [ ] Nodes validate transfers deterministically.
- [ ] Nodes produce and validate blocks.
- [ ] PoI validators can propose and vote on blocks.
- [ ] Finalized blocks are immutable under the protocol's finality rule.
- [ ] Proof-of-Time reward issuance works.
- [ ] Dynamic mining rate uses the canonical formula.
- [ ] Mining rewards can never exceed the 1,000,000,000 ORBIT mining pool.
- [ ] The mining reward reaches zero when the mining pool is exhausted.
- [ ] NodeBoost never exceeds +10%.
- [ ] State roots match across nodes.
- [ ] Block hashes match across nodes.
- [ ] Transaction replay is rejected.
- [ ] Invalid signatures are rejected.
- [ ] Malformed blocks are rejected.
- [ ] Network synchronization works after node restart.
- [ ] A three-node devnet reaches the same finalized state.
- [ ] The explorer can read blocks, transactions, accounts, validators, and mining data.
- [ ] All consensus-critical behavior has deterministic tests.

---

## 52. Immediate Implementation Order

Start with this exact dependency order:

```text
1. Canonical serialization
2. Hash/signature abstraction
3. Transaction model
4. Account/state model
5. Block model
6. Genesis
7. State transition engine
8. Block validation
9. Mining fixed-point math
10. Reward issuance
11. Validator state
12. PoI voting
13. Finality
14. P2P transport
15. Chain synchronization
16. Wallet CLI
17. RPC
18. Explorer
19. Lockups
20. Exchange integration
21. Orbim sandbox
22. Bridges/governance
```

Do not start with the Discord bot, exchange, explorer, or smart contracts. They should consume the stable Orbit core through APIs.

---

## 53. First Code Deliverable

The first executable milestone should be a single-node Sage program capable of:

```text
create genesis
      |
      v
create wallet
      |
      v
create signed transfer
      |
      v
validate transfer
      |
      v
calculate mining rate
      |
      v
create reward transaction
      |
      v
assemble block
      |
      v
validate block
      |
      v
commit new state
      |
      v
print block hash + state root
```

Once this works deterministically, clone the same process into three nodes and begin PoI/network development.

---

## 54. Final Protocol Principle

Orbit should be built as a deterministic state machine first and a cryptocurrency application second.

The central invariant is:

```text
same genesis
+ same valid transactions
+ same consensus rules
+ same protocol inputs
= same block/state result
```

Sage provides the language/runtime foundation. Orbit provides the protocol, monetary system, consensus rules, and network behavior. The implementation should keep those layers explicit so Orbit can evolve without turning Sage itself into a blockchain-specific runtime.
