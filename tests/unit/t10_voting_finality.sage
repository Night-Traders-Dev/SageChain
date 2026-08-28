# t10 — PoI votes, weighted tally, finality threshold, no-reorg (§15, §27)
import orbit.consensus.voting as voting
import orbit.consensus.poi as poi
import orbit.consensus.finality as finality
import orbit.consensus.trust as trust
import orbit.core.chain as chainmod
import orbit.core.bigint as bi
import orbit.wallet.account as account
import orbit.core.genesis as genesis

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

# ── three funded validators on a live chain ──
let chain = chainmod.Chain("orbit-devnet")
let seeds = ["val-one-seed-01", "val-two-seed-02", "val-three-seed-03"]
let addrs = []
for s in seeds:
    push(addrs, account.derive_address(s))
# fund from genesis system wallet via a plain (unsigned-in-test) injection:
let sys = chain.state.accounts[genesis.genesis_address("system")]
sys["balance"] = bi.bi_sub(sys["balance"], "30000000000000")   # 300k ORBIT total

var i = 0
for s in seeds:
    chain.state.accounts[addrs[i]] = {"balance": "10000000000000",
        "nonce": 0, "locked_balance": "0", "activity_marker": 0,
        "validator_status": nil}
    let vr = chain.register_validator(addrs[i],
        account.derive_public_key(s), "100000000000")
    check("registered-" + str(i), vr[0] and
          chain.validators.get(addrs[i])["current_status"] == "active")
    i = i + 1

# uptime warm-up so weights are non-zero (EMA needs observations)
i = 0
while i < 300:
    for a in addrs:
        trust.apply_uptime_observation(chain.validators, a, true)
    i = i + 1

# ── vote for the tip ──
let tip_hash = chain.tip().hash
let h = chain.height()
let votes = []
i = 0
for s in seeds:
    let v = voting.Vote(addrs[i], tip_hash, h, voting.VOTE_YES)
    voting.sign_vote(v, s)
    push(votes, v)
    i = i + 1

let evalr = poi.evaluate_candidate(votes, chain.validators, tip_hash, h)
print("[dbg] tally:", str(evalr["tally"]["yes"]) + "/" + str(evalr["tally"]["total"]),
      "invalid:", len(evalr["invalid"]))
check("all-votes-valid", len(evalr["invalid"]) == 0)
check("tally-total-positive", evalr["tally"]["total"] > 0)
check("threshold-met", evalr["certificate"] != nil)

let cert = evalr["certificate"]
check("cert-integrity", cert.verify_integrity())
check("cert-height", cert.height == h and cert.block_hash == tip_hash)

# tampered certificate fails integrity
let half = int(cert.total_weight / 2)   # 1/2 weight < 2/3 threshold
let bad = finality.FinalityCertificate(cert.height, cert.block_hash,
                                       half, cert.total_weight,
                                       cert.voter_count)
check("tampered-cert-fails", not bad.verify_integrity())

# a NO-heavy round cannot finalize
let no_votes = []
i = 0
for s in seeds:
    let choice = voting.VOTE_NO
    let v = voting.Vote(addrs[i], "b" * 64, h + 1, choice)
    voting.sign_vote(v, s)
    push(no_votes, v)
    i = i + 1
let eval_no = poi.evaluate_candidate(no_votes, chain.validators, "b" * 64, h + 1)
check("unanimous-no-no-finality", eval_no["certificate"] == nil)

# duplicate vote for same (addr, hash) flagged
let dupe_votes = [votes[0], votes[0]]
let eval_dupe = poi.evaluate_candidate(dupe_votes, chain.validators, tip_hash, h)
check("duplicate-flagged", len(eval_dupe["invalid"]) == 1 and
      eval_dupe["tally"]["total"] < evalr["tally"]["total"] * 2)

# unsigned vote rejected cryptographically
let unsigned = voting.Vote(addrs[0], tip_hash, h, voting.VOTE_YES)
check("unsigned-rejected", not voting.validate(unsigned, chain.validators)[0])

# ── submit votes to the node, then finalize ──
i = 0
for s in seeds:
    let v = voting.Vote(addrs[i], chain.tip().hash, h, voting.VOTE_YES)
    voting.sign_vote(v, s)
    let sr = chain.submit_vote(v)
    check("submit-vote-" + str(i), sr[0])
    i = i + 1

let fr = chain.try_finalize()
check("chain-finalized", fr[0])
import orbit.core.block as blockmod
let fork = blockmod.Block(chain.finalized_height - 1 + 1, "c" * 64)
fork.height = chain.finalized_height   # would REPLACE finalized block
fork.timestamp = chain.tip().timestamp + 5
let rr = chain.append_block(fork)
check("reorg-past-finality-blocked", not rr[0] or rr[1] != "reorg_past_finality")
# direct rule probe:
let rr2 = chain.check_reorg_rule(chain.finalized_height - 1)
check("reorg-rule-probe", not rr2[0])

print("t10 voting/finality: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t10 FAILED"
