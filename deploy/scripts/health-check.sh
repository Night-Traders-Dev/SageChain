#!/bin/bash
# Orbit Blockchain - Health Check Script
# Used by monitoring systems (Prometheus, Consul, etc.)

set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
EXPLORER_URL="${EXPLORER_URL:-http://127.0.0.1:3000}"
TIMEOUT=5

check_rpc() {
    local response
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"status","params":[],"id":1}' \
        --max-time "$TIMEOUT" "$RPC_URL" 2>/dev/null) || return 1

    if echo "$response" | grep -q '"height"'; then
        return 0
    fi
    return 1
}

check_explorer() {
    local response
    response=$(curl -s --max-time "$TIMEOUT" "$EXPLORER_URL/health" 2>/dev/null) || return 1
    return 0
}

check_node_sync() {
    local response
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"status","params":[],"id":1}' \
        --max-time "$TIMEOUT" "$RPC_URL" 2>/dev/null) || return 1

    local height finalized
    height=$(echo "$response" | grep -o '"height":[0-9]*' | cut -d: -f2)
    finalized=$(echo "$response" | grep -o '"finalized_height":[0-9]*' | cut -d: -f2)

    if [[ -n "$height" && -n "$finalized" ]]; then
        local lag=$((height - finalized))
        if [[ $lag -le 10 ]]; then
            return 0
        fi
    fi
    return 1
}

check_disk_space() {
    local available
    available=$(df /opt/orbit/data --output=avail | tail -1 | tr -d ' ')
    # Require at least 1GB free
    if [[ $available -gt 1048576 ]]; then
        return 0
    fi
    return 1
}

main() {
    local failed=0

    if ! check_rpc; then
        echo "RPC: FAIL"
        failed=1
    else
        echo "RPC: OK"
    fi

    if ! check_explorer; then
        echo "Explorer: FAIL"
        failed=1
    else
        echo "Explorer: OK"
    fi

    if ! check_node_sync; then
        echo "Sync: FAIL (lag > 10 blocks)"
        failed=1
    else
        echo "Sync: OK"
    fi

    if ! check_disk_space; then
        echo "Disk: FAIL (< 1GB free)"
        failed=1
    else
        echo "Disk: OK"
    fi

    exit $failed
}

main "$@"