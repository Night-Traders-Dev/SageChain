# tools/gen_mining_vectors.sage — regenerate tests/vectors/mining_vectors.sage
# Run: sage-c tools/gen_mining_vectors.sage   (from repo root)
import orbit.mining.rate as rate
import orbit.core.bigint as bi

let CASES = [
    {"name": "vector_1", "users": 1000,   "remaining": "90000000000000000",  "height": 10000,  "score": 900000, "eligible_seconds": 60},
    {"name": "vector_2", "users": 10000,  "remaining": "50000000000000000",  "height": 50000,  "score": 800000, "eligible_seconds": 60},
    {"name": "vector_3", "users": 50000,  "remaining": "20000000000000000",  "height": 100000, "score": 600000, "eligible_seconds": 60},
    {"name": "vector_4", "users": 100000, "remaining": "0",                  "height": 200000, "score": 1000000, "eligible_seconds": 60},
]
proc rewards_for(rate_value, secs, pool):
    import orbit.mining.rewards as rewards
    return rewards.calculate_block_reward(rate_value, secs, pool)

print("GENERATED — do not edit by hand")
for c in CASES:
    let r = rate.calculate_mining_rate(c["users"], c["remaining"], c["height"], c["score"])
    let rw = rewards_for(r, c["eligible_seconds"], c["remaining"])
    print(c["name"] + "|" + str(c["users"]) + "|" + c["remaining"] + "|" +
          str(c["height"]) + "|" + str(c["score"]) + "|" + r + "|" + rw)
