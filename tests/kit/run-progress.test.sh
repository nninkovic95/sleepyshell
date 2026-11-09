#!/bin/bash
# kit/run-progress.test.sh [TREE]: run.sh shows where a long run is: each test's header carries its place in the run,
# [n/N], and after each test one line counts the tests done so far, ok and failed; the totals stay last.
#
# Tier 4 (a long run gives no idea how far it is): runs run.sh itself on two short tests and reads its output. Only
# this test's own PASS/FAIL lines are printed (the inner run's checks would otherwise count twice). Prints PASS or FAIL
# per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
A=bar/keyreport.test.sh
B=settings/keyreport-writer.test.sh
out=$(bash "$KIT/run.sh" --no-selftest --tree "$TREE" "$A" "$B" 2>&1)
rc=0
check() {   # check DESCRIPTION CONDITION...
    local what=$1
    shift
    if "$@"; then echo "PASS $what"; else echo "FAIL $what"; rc=1; fi
}
lines() { printf '%s\n' "$out" | grep -nE "$1" | cut -d: -f1 | head -1; }
h1=$(lines "^== \[1/2\] $A$")
h2=$(lines "^== \[2/2\] $B$")
c1=$(lines "^-- 1 of 2 done: (1 ok, 0 failed|0 ok, 1 failed)$")
c2=$(lines "^-- 2 of 2 done: [0-2] ok, [0-2] failed$")
tot=$(lines "^2 tests, [0-9]+ failed$")
check "the first test's header shows its place, [1/2]" test -n "$h1"
check "the second test's header shows its place, [2/2]" test -n "$h2"
check "after the first test, a line counts the tests done so far" test -n "$c1"
check "after the second test, the count reaches 2 of 2" test -n "$c2"
check "the counts come after their test's header and before the next" \
    test -n "$h1$c1$h2$c2" -a "${h1:-0}" -lt "${c1:-0}" -a "${c1:-0}" -lt "${h2:-0}" -a "${h2:-0}" -lt "${c2:-0}"
check "the totals stay the last line" test -n "$tot" -a "$tot" = "$(printf '%s\n' "$out" | wc -l)"
[ "$rc" = 0 ] || printf '%s\n' "$out" | grep -E '^(==|--|[0-9]+ tests)' | head -12 | sed 's/^/    /'
exit "$rc"
