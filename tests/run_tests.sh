#!/usr/bin/env bash
# Orbit test runner — sage-c only (project policy)
set -u
cd "$(dirname "$0")/.."
SAGE="${SAGE_BIN:-sage-c}"
total_fail=0
for t in tests/unit/t*.sage; do
    echo "── $t"
    if ! out=$("$SAGE" "$t" 2>&1); then
        total_fail=$((total_fail+1))
        echo "$out" | sed 's/^/    /'
        continue
    fi
    echo "$out" | grep -E "^t[0-9]+" | sed 's/^/    /'
done
echo "════════════════════════════"
if [ "$total_fail" -eq 0 ]; then
    echo "ALL TEST FILES PASSED (sage-c)"
else
    echo "$total_fail test file(s) FAILED"
    exit 1
fi
