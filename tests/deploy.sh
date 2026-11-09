#!/bin/bash
# deploy.sh plan CANDIDATE       what a deploy would add, change and remove (writes nothing)
# deploy.sh apply CANDIDATE      deploy it; rolls back by itself when the shell does not load afterwards
# deploy.sh rollback [BACKUP]    put the shell back as it was before the newest (or the named) deploy
# deploy.sh list                 the backups, newest last
#
# apply, in order:
#   1. the compile gate (common/compile.sh): nothing is written unless every file compiles
#   2. a backup of the whole live tree, settings file included, to BACKUPS/<date-time>/live.tar.gz,
#      with the plan beside it
#   3. a running preview is stopped and the live settings window closed, so neither reloads on a
#      half-copied tree
#   4. new files first (a reload that fires mid-copy must not meet a file using a type not there yet),
#      then changed files, then known shell files the candidate no longer has are removed, then empty folders
#   5. the live tree must now equal the candidate (state and unknown files aside), else it rolls back;
#      the deploy's manifest (the shell files it put in place) is kept beside the backup as deployed.txt
#   6. the shell is restarted when files were added or removed (a hot reload after a failed mid-copy
#      reload watches only the files it had loaded) and reloaded otherwise; then its log must say
#      "Configuration Loaded", else it rolls back and restarts the old shell
# The user's state (sleepysettings.toml, settings.json and their copies) is never deployed, removed
# or restored, and neither are the repository's own files (.git, tests/, docs/, README and the other
# root documents; the list is REPO_DIRS/REPO_FILES in common/env.sh). A file the live tree has and the
# candidate lacks is removed only when it is a known shell file: tracked by git in the live checkout,
# or put in place by an earlier deploy (its deployed.txt); anything else is reported as unknown and
# left alone, since the live tree is the repository checkout and holds files that are not the shell's.
# With SLEEPYSHELL_LIVE set to a scratch copy the script tests itself: it then never stops, starts or
# reloads a shell (kit/deploy-unknown-files.test.sh).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common/env.sh"
REAL=no
[ "$(readlink -m "$LIVE")" = "$(readlink -m "$REAL_LIVE")" ] && REAL=yes

# known_files [PATH...]: the shell files a deploy may remove, one per line: tracked by git in the live
# checkout, listed by an earlier deploy's manifest, or given (a rollback: what the undone deploy added)
known_files() {
    { git -C "$LIVE" ls-files 2>/dev/null || true
      cat "$BACKUPS"/*/deployed.txt 2>/dev/null || true
      if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; fi
    } | sort -u
}

# plan_json SRC DST [KNOWN...]: the plan as JSON (common/treediff.py)
plan_json() {
    local k
    k=$(mktemp)
    known_files "${@:3}" >"$k"
    python3 -I "$KIT/common/treediff.py" "$1" "$2" "$k"
    rm -f -- "$k"
}

# field of a plan: new, changed or removed, one path per line
field() {
    python3 -I -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$1" "$2"
}

copy_plan() {
    # copy_plan SRC PLAN: make LIVE equal to SRC following PLAN
    local src=$1 plan=$2 f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        mkdir -p -- "$LIVE/$(dirname -- "$f")"
        cp -p -- "$src/$f" "$LIVE/$f"
    done < <(field "$plan" new)
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        cp -p -- "$src/$f" "$LIVE/$f"
    done < <(field "$plan" changed)
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rm -f -- "$LIVE/$f"
        # the folders this removal emptied, up to the tree root; a folder that was empty before stays
        d=$(dirname -- "$f")
        while [ "$d" != "." ] && rmdir -- "$LIVE/$d" 2>/dev/null; do
            d=$(dirname -- "$d")
        done
    done < <(field "$plan" removed)
}

counts() {
    python3 -I -c 'import json,sys; p=json.load(open(sys.argv[1])); print(len(p["new"]), "new,", len(p["changed"]), "changed,", len(p["removed"]), "removed")' "$1"
}

# the unknown files of a plan, as one line for the log ("" when there are none)
unknowns() {
    python3 -I -c 'import json,sys; u=json.load(open(sys.argv[1]))["unknown"]; print(f"{len(u)} unknown file(s) left alone: " + ", ".join(u[:8]) + (" …" if len(u) > 8 else "") if u else "")' "$1"
}

quiet_shells() {
    # stop a preview and close the live settings window before files change
    local p
    p=$(preview_pid)
    [ -n "$p" ] && { stop_pid "$p"; echo "deploy: preview stopped"; }
    qs -p "$LIVE/sleepysettings.qml" ipc call sleepysettings close >/dev/null 2>&1 || true
}

# bring_up RESTART: restart (yes) or reload (no) the live shell and wait for its load result
bring_up() {
    local restart=$1 pid n f
    pid=$(live_shell_pid)
    if [ "$restart" = yes ] || [ -z "$pid" ]; then
        [ -n "$pid" ] && stop_pid "$pid"
        pid=$(start_shell)
        [ -n "$pid" ] || { echo "no process"; return 1; }
        wait_loaded 0 "$pid"
    else
        n=$(load_count "$pid")
        sleep 1
        for f in sleepybar/Sleepybar.qml sleepybar/Bar.qml; do
            [ -f "$LIVE/$f" ] && { touch "$LIVE/$f"; break; }
        done
        r=$(wait_loaded "$n" "$pid") && { echo "$r"; return 0; }
        [ "$r" = timeout ] || { echo "$r"; return 1; }
        # the touch did not reload (Quickshell's file watch does not always fire): restart instead
        stop_pid "$pid"
        pid=$(start_shell)
        [ -n "$pid" ] || { echo "no process"; return 1; }
        wait_loaded 0 "$pid"
    fi
}

newest_backup() {
    ls -d "$BACKUPS"/*/ 2>/dev/null | grep -v '\.rolled-back/$' | sort | tail -1 | sed 's|/$||'
}

rollback() {
    local B=$1 T plan
    [ -f "$B/live.tar.gz" ] || { echo "deploy: $B has no live.tar.gz"; return 1; }
    T=$RUN/rollback-$$
    mkdir -p "$T"
    tar -C "$T" -xzf "$B/live.tar.gz"
    plan=$T.plan.json
    # what the undone deploy added is known too: it goes again
    mapfile -t added < <(field "$B/plan.json" new)
    plan_json "$T" "$LIVE" "${added[@]}" > "$plan"
    echo "deploy: rollback to $(basename "$B"): $(counts "$plan")"
    [ "$REAL" = yes ] && quiet_shells
    copy_plan "$T" "$plan"
    plan_json "$T" "$LIVE" "${added[@]}" > "$plan"
    if [ "$(counts "$plan")" != "0 new, 0 changed, 0 removed" ]; then
        echo "deploy: rollback left differences: $(counts "$plan")"
        rm -rf -- "$T" "$plan"
        return 1
    fi
    rm -rf -- "$T" "$plan"
    mv -- "$B" "$B.rolled-back"
    if [ "$REAL" = yes ]; then
        echo "deploy: shell after rollback: $(bring_up yes || true)"
    fi
}

case "${1:-}" in
plan)
    C=$(readlink -f "${2:?candidate}")
    p=$(plan_json "$C" "$LIVE")
    echo "$p" | python3 -I -c '
import json, sys
p = json.load(sys.stdin)
for k, title in (("new", "new"), ("changed", "changed"), ("removed", "removed"), ("unknown", "unknown, left alone")):
    print(f"{title} ({len(p[k])}):")
    for f in p[k]:
        print("   ", f)'
    ;;
apply)
    C=$(readlink -f "${2:?candidate}")
    [ "$C" = "$(readlink -f "$LIVE")" ] && { echo "deploy: the candidate is the live tree"; exit 2; }
    bash "$KIT/common/compile.sh" "$C" | tail -3
    stamp=$(date +%Y-%m-%d-%H%M%S)
    B=$BACKUPS/$stamp
    mkdir -p "$B"
    plan_json "$C" "$LIVE" > "$B/plan.json"
    if [ "$(counts "$B/plan.json")" = "0 new, 0 changed, 0 removed" ]; then
        rm -rf -- "$B"
        echo "deploy: nothing differs"
        exit 0
    fi
    tar -C "$LIVE" $(tar_excludes) -czf "$B/live.tar.gz" .
    echo "$C" > "$B/candidate.txt"
    echo "deploy: $(counts "$B/plan.json"); backup $stamp"
    u=$(unknowns "$B/plan.json")
    [ -n "$u" ] && echo "deploy: $u"
    [ "$REAL" = yes ] && quiet_shells
    copy_plan "$C" "$B/plan.json"
    # (unknown files stay, so they are not differences)
    check=$(plan_json "$C" "$LIVE" | python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(len(p["new"]) + len(p["changed"]) + len(p["removed"]))')
    if [ "$check" != 0 ]; then
        echo "deploy: the live tree does not match the candidate after copying; rolling back"
        rollback "$B"
        exit 1
    fi
    python3 -I "$KIT/common/treediff.py" --files "$C" > "$B/deployed.txt"
    echo "deploy: files in place"
    if [ "$REAL" = yes ]; then
        restart=no
        python3 -I -c 'import json,sys; p=json.load(open(sys.argv[1])); sys.exit(0 if p["new"] or p["removed"] else 1)' "$B/plan.json" && restart=yes
        if r=$(bring_up "$restart"); then
            echo "deploy: shell $r ($([ "$restart" = yes ] && echo restarted || echo reloaded))"
        else
            echo "deploy: the shell did not load ($r); rolling back"
            pid=$(live_shell_pid)
            [ -n "$pid" ] && qs log --pid "$pid" 2>/dev/null | grep -aE 'ERROR|caused by' | tail -6
            rollback "$B"
            exit 1
        fi
    fi
    echo "deploy: done; undo with: $0 rollback $stamp"
    ;;
rollback)
    if [ -n "${2:-}" ]; then B=$BACKUPS/$2; else B=$(newest_backup); fi
    [ -n "$B" ] && [ -d "$B" ] || { echo "deploy: no backup to roll back to"; exit 1; }
    rollback "$B"
    ;;
list)
    ls -1 "$BACKUPS" 2>/dev/null || true
    ;;
*)
    sed -n '2,5p' "$0"
    exit 2
    ;;
esac
