#!/bin/bash
# bar/islandshape.test.sh [TREE]: the centre island's outline component (sleepybar/components/IslandShape.qml) on its
# own, with Qt Quick Test: one path, never swapped for another drawing; smooth; only growing while it opens; never
# crossing itself; the right size at both ends. Tier 4 (cosmetic) for the standing requirement that each island is one
# single shape: a broken outline shows as a seam, a jump or a corner drawn as its own piece. Also the island's size
# rules (CentreGeometry.js, tst_centregeometry.qml) on their own, against hand-worked examples.
#
# IslandShape imports only QtQuick and QtQuick.Shapes, so it runs under qmltestrunner without Quickshell (offscreen,
# software scene graph: no GPU, no compositor). CMD below is also the CI job's command, word for word, run from the
# repository root (.github/workflows/islandshape.yml); a tree with the repository's files is checked for that. Here
# the tree's component and the test files are copied into a run folder in the repository's layout, and CMD runs there
# inside the sandbox with the checksum guard around it. Prints PASS or FAIL per test function; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
# (the results go to stdout and, for the CI job's summary, to a file in /tmp: the sandbox's own /tmp here)
CMD='env QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -platform offscreen -input tests/bar/islandshape -o -,txt -o /tmp/islandshape-results.txt,txt'
NAME=islandshape-$$
D=$RUN/$NAME
mkdir -p "$D/t/sleepybar/components" "$D/t/tests/bar"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
for f in IslandShape.qml CentreGeometry.js; do
    [ -f "$TREE/sleepybar/components/$f" ] && cp "$TREE/sleepybar/components/$f" "$D/t/sleepybar/components/"
done
cp -r "$KIT/bar/islandshape" "$D/t/tests/bar/"

timeout 300 bash "$KIT/common/sandbox.sh" "$D" bash -c "cd t && exec $CMD" >"$D/out.txt" 2>&1
rc=$?
# qmltestrunner's own lines -> the kit's PASS/FAIL lines (the failure's message and location on the next lines)
awk '
    /^PASS   : / { sub(/^PASS   : [^:]*::/, ""); if ($0 !~ /initTestCase|cleanupTestCase/) print "PASS " $0; next }
    /^FAIL!  : / { sub(/^FAIL!  : [^:]*::/, ""); fail = "FAIL " $0; print fail; next }
    /^   (Actual|Expected|Loc)/ { if (fail) print "     " $0; next }
    /^QWARN|^QCRITICAL|^QFATAL/ { print "     " $0; next }
    /module .* is not installed|is not a type|Type .* unavailable/ { print "FAIL " $0 }
' "$D/out.txt"
grep -q "^Totals:" "$D/out.txt" || { echo "FAIL qmltestrunner did not finish:"; tail -5 "$D/out.txt" | sed 's/^/    /'; rc=1; }
# a run that found no test passes nothing
grep -q "^PASS   : .*::test_" "$D/out.txt" || { echo "FAIL no test ran"; rc=1; }
# on a failure, the lines qmltestrunner printed that are not test results (load errors name the file and line there)
[ "$rc" = 0 ] || grep -E "\.qml:[0-9]+" "$D/out.txt" | grep -v "^FAIL!" | head -12 | sed 's/^ */    /'
# CI runs CMD itself: a different command there would test something else than this run did. A shell tree copied
# without the repository's files (a candidate) has no CI job to compare.
WF=$TREE/.github/workflows/islandshape.yml
if [ -d "$TREE/.github" ]; then
    # the whole line, whatever its indent: an argument added in CI fails too
    if sed 's/^[[:space:]]*//' "$WF" 2>/dev/null | grep -qxF -- "run: $CMD"; then
        echo "PASS the CI job runs this same command"
    else
        echo "FAIL the CI job does not run this same command ($WF)"
        rc=1
    fi
else
    echo "SKIP the CI job's command: this tree has no .github"
fi
if ! python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null; then
    echo "FAIL a real file changed"
    rc=1
fi
[ "$rc" = 0 ] || exit 1
