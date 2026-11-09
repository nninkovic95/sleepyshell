#!/bin/bash
# kit/deploy-unknown-files.test.sh [TREE]: deploy.sh never removes a file it does not recognise.
#
# Tier 1 (a deploy deletes something of the user's): the live tree is the repository checkout, so it holds files that
# are not the shell's (notes, backups, tool configuration). A deploy removes a file the candidate lacks only when it
# is a known shell file: tracked by git in the live checkout, or listed by an earlier deploy's manifest. Anything else
# is reported as unknown and left in place; .worktreeinclude is a repository file and never listed. Runs deploy.sh in
# its self-test mode (SLEEPYSHELL_LIVE and SLEEPYSHELL_BACKUPS on scratch copies: no shell is stopped, started or
# reloaded) on small trees of its own. TREE is not used. Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
NAME=deploy-unknown-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT
python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
rc=0
check() {   # check DESCRIPTION CONDITION...
    local what=$1
    shift
    if "$@"; then echo "PASS $what"; else echo "FAIL $what"; rc=1; fi
}
qml() { mkdir -p "$(dirname "$1")"; printf 'import QtQuick\nItem {}\n' >"$1"; }
# a tree the compile gate accepts: shell.qml plus a type at the root (the gate imports the root module)
tree() { qml "$1/shell.qml"; qml "$1/Root.qml"; }

# the live tree: a git checkout with four shell files, plus files that are not the shell's
L=$D/live
tree "$L"; qml "$L/sleepybar/A.qml"; qml "$L/sleepybar/B.qml"
echo "tests/" >"$L/.worktreeinclude"
G=(git -C "$L" -c user.name=kit -c user.email=kit@localhost -c core.hooksPath=/dev/null)
"${G[@]}" init -q
"${G[@]}" add shell.qml Root.qml sleepybar .worktreeinclude
"${G[@]}" commit -q -m base
echo "my notes" >"$L/notes.txt"                 # untracked, never deployed
qml "$L/sleepybar/Scratch.qml"                  # untracked, never deployed
echo "backup" >"$L/TASKS.md.bak-test"            # untracked, never deployed

# deploy 1: the candidate drops the tracked B.qml and adds C.qml
C1=$D/cand1
tree "$C1"; qml "$C1/sleepybar/A.qml"; qml "$C1/sleepybar/C.qml"
export SLEEPYSHELL_LIVE=$L SLEEPYSHELL_BACKUPS=$D/backups
plan=$(bash "$KIT/deploy.sh" plan "$C1" 2>&1)
removed=$(printf '%s\n' "$plan" | sed -n '/^removed/,/^[a-z]/p' | grep '^    ' | sed 's/^ *//')
check "plan: the tracked shell file the candidate drops is to be removed" grep -qx "sleepybar/B.qml" <<<"$removed"
check "plan: no unknown file is to be removed" test -z "$(grep -vx 'sleepybar/B.qml' <<<"$removed")"
check "plan: the unknown files are reported as left alone" \
    bash -c 'grep -q "^unknown" <<<"$1" && grep -q "notes.txt" <<<"$1" && grep -q "sleepybar/Scratch.qml" <<<"$1"' _ "$plan"
check "plan: .worktreeinclude is never listed" bash -c '! grep -q "worktreeinclude" <<<"$1"' _ "$plan"

out=$(bash "$KIT/deploy.sh" apply "$C1" 2>&1)
check "apply: the deploy succeeds with unknown files present" grep -q "^deploy: done" <<<"$out"
check "apply: B.qml is gone and C.qml is in place" test ! -e "$L/sleepybar/B.qml" -a -f "$L/sleepybar/C.qml"
check "apply: every unknown file is still there" \
    test -f "$L/notes.txt" -a -f "$L/sleepybar/Scratch.qml" -a -f "$L/TASKS.md.bak-test" -a -f "$L/.worktreeinclude"

# deploy 2: C.qml was deployed but never committed; a candidate without it removes it (the manifest knows it)
C2=$D/cand2
tree "$C2"; qml "$C2/sleepybar/A.qml"
sleep 1   # (backups are named by the second)
out=$(bash "$KIT/deploy.sh" apply "$C2" 2>&1)
check "a file an earlier deploy put in place is removed when the candidate drops it" \
    bash -c 'grep -q "^deploy: done" <<<"$1" && test ! -e "$2"' _ "$out" "$L/sleepybar/C.qml"
check "the unknown files survive a second deploy" test -f "$L/notes.txt" -a -f "$L/sleepybar/Scratch.qml"

# rollback of deploy 2 brings C.qml back and leaves the unknown files alone
out=$(bash "$KIT/deploy.sh" rollback 2>&1)
check "rollback restores the removed file and keeps the unknown ones" \
    bash -c 'test -f "$1/sleepybar/C.qml" -a -f "$1/notes.txt" -a -f "$1/sleepybar/Scratch.qml"' _ "$L"
[ "$rc" = 0 ] || { echo "    plan was:"; printf '%s\n' "$plan" | sed 's/^/      /'; echo "    last output:"; printf '%s\n' "$out" | tail -8 | sed 's/^/      /'; }
if ! python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null; then
    echo "FAIL a real file changed"
    rc=1
fi
exit "$rc"
