# SECURITY — Threat Model

Status: draft (§37)

## Threats

Sybil validators · fake uptime · clock manipulation · reward duplication ·
double spending · malformed blocks · invalid signatures · replayed
transactions · peer flooding · fork attacks · state corruption · validator
collusion · exchange manipulation · wallet key theft.

## Required protections

Transaction nonces · chain/network IDs inside signed data · deterministic
serialization · signature validation · bounded timestamp drift · validator
penalties · replay protection · block & tx size limits · peer rate limiting ·
state-root verification · finality certificates · atomic state commits.

## Invariants with automated tests (§38)

    circulating_supply <= TOTAL_SUPPLY
    0 <= mining_remaining <= MINING_SUPPLY
    balance >= 0 ; locked_balance >= 0
    block[n].previous_hash == block[n-1].hash
    reward_minted <= pool_remaining_before_block
    inputs + permitted_mint == outputs + fees

Private keys never appear on chain or in API responses (§23, §31).
