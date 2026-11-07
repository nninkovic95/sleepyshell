#!/bin/bash
# run.sh [--twice] [--watch] [--update-refs] [--no-selftest] [AREA|TEST...]: run the suite, or some areas or tests.
#
#   bash tests/run.sh                       selftest, then every test of every area
#   bash tests/run.sh settings              one area (a folder: settings, keys, bar, lock, kit, install)
#   bash tests/run.sh settings/export.test.py   one test
#   --twice        run each test twice and fail when the two runs print different results (determinism)
#   --watch        share the private test screen live and view-only in a VNC viewer on the desktop (wayvnc on a Unix
#                  socket in the run folder; the viewer gets no input in and the sandbox no network out)
#   --tree PATH    test that tree (a candidate copy) instead of the live shell
#   --update-refs  keep each screenshot check's image in tests/jobs/failed/ as a candidate reference instead of comparing;
#                  copying a candidate to tests/refs/ is a separate step, done by hand
#
# A test is <area>/<name>.test.sh (a script that prints PASS/FAIL lines and exits 1 on a failure) or <area>/<name>.test.py
# (a whole-window test run through common/ui/run-ui.sh). Every other file in an area folder is a helper. Prints each
# test's PASS/FAIL lines, then one summary line per test and the totals; exits 1 if any test failed.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/common/env.sh"
AREAS=(settings keys bar lock kit install)
TWICE=0 SELFTEST=1 TREE=
args=()
next_is_tree=0
for a in "$@"; do
    if [ "$next_is_tree" = 1 ]; then
        TREE=$(readlink -f "$a")
        next_is_tree=0
        continue
    fi
    case "$a" in
        --tree) next_is_tree=1 ;;
        --twice) TWICE=1 ;;
        --watch) export SLEEPYSHELL_WATCH=1 ;;
        --update-refs) export SLEEPYSHELL_UPDATE_REFS=1 ;;
        --no-selftest) SELFTEST=0 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) args+=("$a") ;;
    esac
done
[ "${#args[@]}" -gt 0 ] || args=("${AREAS[@]}")

tests=()
for a in "${args[@]}"; do
    a=${a#tests/}
    if [ -f "$KIT/$a" ]; then
        tests+=("$a")
    elif [ -d "$KIT/$a" ]; then
        while IFS= read -r t; do tests+=("${t#"$KIT"/}"); done < <(find "$KIT/$a" -maxdepth 1 -name '*.test.sh' -o -maxdepth 1 -name '*.test.py' | sort)
    else
        echo "run: no test or area $a"
        exit 2
    fi
done

if [ "$SELFTEST" = 1 ]; then
    echo "== selftest"
    if ! bash "$KIT/common/selftest.sh"; then
        echo "selftest failed: no test was run"
        exit 1
    fi
fi

one() {
    local t=$1 name
    name=$(basename "$t")
    name=${name%.test.*}
    case "$t" in
        *.test.py) bash "$KIT/common/ui/run-ui.sh" "$(dirname "$t")-$name" "$KIT/$t" ${TREE:+"$TREE"} ;;
        *) bash "$KIT/$t" ${TREE:+"$TREE"} ;;
    esac
}

summary=()
failed=0
for t in "${tests[@]}"; do
    echo "== $t"
    start=$SECONDS
    out=$(one "$t" 2>&1)
    rc=$?
    echo "$out"
    if [ "$TWICE" = 1 ]; then
        echo "== $t (second run)"
        out2=$(one "$t" 2>&1)
        rc2=$?
        echo "$out2"
        a=$(echo "$out" | grep -E '^(PASS|FAIL) ' | sed 's/: .*//')
        b=$(echo "$out2" | grep -E '^(PASS|FAIL) ' | sed 's/: .*//')
        [ "$a" = "$b" ] || { echo "FAIL $t gave different results on the second run"; rc=1; }
        [ "$rc2" = 0 ] || rc=1
    fi
    n_pass=$(echo "$out" | grep -c '^PASS ')
    n_fail=$(echo "$out" | grep -c '^FAIL ')
    secs=$((SECONDS - start))
    if [ "$rc" = 0 ] && [ "$n_fail" = 0 ] && [ "$n_pass" -gt 0 ]; then
        summary+=("ok      $t ($n_pass checks, ${secs}s)")
    else
        summary+=("FAILED  $t ($n_pass passed, $n_fail failed, ${secs}s)")
        failed=$((failed + 1))
    fi
done

echo "== summary"
printf '%s\n' "${summary[@]}"
echo "${#tests[@]} tests, $failed failed"
[ "$failed" = 0 ]
