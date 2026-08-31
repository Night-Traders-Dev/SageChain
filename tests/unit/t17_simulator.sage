# t17 — economics simulator test (§45)
import orbit.simulator.simulator as sim

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

# Test 1: Rate calculation at genesis
let params = {
    "r_base": "8200000",
    "u_target": 10000,
    "s_max": "100000000000000000",
    "b_halflife": 100000,
    "node_boost_max": 100000,
}

let state = sim.NetworkState({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000, "blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100, "max_block_time": 500})
state.block_height = 0
state.mining_pool = "100000000000000000"

# Add some users
state.add_users(10000)

let rate = sim.calculate_rate({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000}, state)
check("rate-genesis", rate != "0")

# Test 2: Rate decreases over time (supply factor)
state2 = sim.NetworkState({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000, "blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100, "max_block_time": 500})
state2.block_height = 0
state2.mining_pool = "100000000000000000"
state2.add_users(10000)
let rate2 = sim.calculate_rate({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000}, state2)

state3 = sim.NetworkState({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000, "blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100, "max_block_time": 500})
state3.block_height = 0
state3.mining_pool = "50000000000000000"
state3.add_users(10000)
let rate3 = sim.calculate_rate({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000}, state3)

check("rate-supply-decreases", bi.bi_cmp(rate2, rate3) > 0)

# Test 3: Time decay
state4 = sim.NetworkState({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000, "blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100, "max_block_time": 500})
state4.block_height = 0
state4.mining_pool = "100000000000000000"
state4.add_users(10000)
let rate4 = sim.calculate_rate({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000}, state4)

state5 = sim.NetworkState({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000, "blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100, "max_block_time": 500})
state5.block_height = 100000  # 1 halflife
state5.mining_pool = "100000000000000000"
state5.add_users(10000)
let rate5 = sim.calculate_rate({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000}, state5)

check("rate-time-decay", bi.bi_cmp(rate4, rate5) > 0)

# Test 4: Supply factor decreases as pool depletes
state6 = sim.NetworkState({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000, "blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100, "max_block_time": 500})
state6.block_height = 0
state6.mining_pool = "100000000000000000"
state6.add_users(10000)
let rate6 = sim.calculate_rate({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000}, state6)

state7 = sim.NetworkState({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000, "blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100, "max_block_time": 500})
state7.block_height = 0
state7.mining_pool = "10000000000000000"
state7.add_users(10000)
let rate7 = sim.calculate_rate({"r_base": "8200000", "u_target": 10000, "s_max": "100000000000000000", "b_halflife": 100000, "node_boost_max": 100000}, state7)

check("rate-supply-factor", bi.bi_cmp(rate6, rate7) > 0)

# Test 5: Block reward calculation
let reward1 = sim.calculate_block_reward("8200000", 500, "100000000000000000")
check("reward-positive", bi.bi_cmp(reward1, "0") > 0)

# Test 6: Reward capped by pool
let reward2 = sim.calculate_block_reward("8200000", 500, "1000")
check("reward-capped", reward2 == "1000")

# Test 7: Lockup reward
let lockup = {"amount": "100000000000", "lock_height": 0}
let lockup_reward = sim.calculate_lockup_reward(lockup, 10000, {"blocks_per_year": 63072, "apr_numerator": 5, "apr_denominator": 100})
check("lockup-reward-positive", bi.bi_cmp(lockup_reward, "0") > 0)

# Test 8: Full simulation run (small)
let sim_instance = sim.Simulator()
let result = sim_instance.run(10, 1, 3)
check("simulation-runs", result["final_height"] == 10)
check("simulation-pool-decreases", bi.bi_cmp(result["final_pool"], "100000000000000000") < 0)
check("simulation-circulating-increases", bi.bi_cmp(result["final_circulating"], "1000000000000000000") > 0)

print("t17 simulator: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t17 FAILED"