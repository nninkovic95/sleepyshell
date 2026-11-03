#!/usr/bin/env bash
# merge-dev.sh: bring dev into main, leaving out every dev-only path listed in .github/dev-only.
#
#   tools/merge-dev.sh [--dry-run] [--push] [--no-fetch]
#
# The working tree stays on dev the whole time (it may be a live config folder): main is built with git
# plumbing, never checked out. Two steps:
#   1. Back-sync, only when main holds changes dev lacks (a commit pushed straight to main): main is
#      merged into dev with dev's own dev-only paths kept, and dev is fast-forwarded to that merge. This
#      is the one step that changes files in the working tree.
#   2. Forward merge: dev now contains all of main, so the new main is exactly dev's tree minus the
#      dev-only paths, committed with parents (main, dev). It is built, not merged, so it cannot conflict,
#      and repeated merges never accumulate anything.
# A plain "git merge main" on dev would delete the dev-only paths from dev; use this script instead.
set -euo pipefail

DRY=0 PUSH=0 FETCH=1
for arg in "$@"; do
    case $arg in
    --dry-run) DRY=1 ;;
    --push) PUSH=1 ;;
    --no-fetch) FETCH=0 ;;
    -h | --help)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "merge-dev: unknown option $arg" >&2
        exit 2
        ;;
    esac
done

die() {
    echo "merge-dev: $*" >&2
    exit 1
}

top=$(git rev-parse --show-toplevel)
cd "$top"
# shellcheck source=../.github/scripts/devonly.sh
source .github/scripts/devonly.sh

[[ $(git symbolic-ref --quiet --short HEAD || true) == dev ]] || die "check out dev first (the working tree stays on dev)"
git diff --quiet && git diff --cached --quiet || die "commit or stash the working tree's changes first"
git rev-parse --verify --quiet refs/heads/main >/dev/null || die "no local main branch"

if ((FETCH)); then
    git fetch --quiet origin
fi
for b in main dev; do
    if git rev-parse --verify --quiet "refs/remotes/origin/$b" >/dev/null; then
        git merge-base --is-ancestor "origin/$b" "$b" ||
            die "$b is behind or has diverged from origin/$b; bring it up to date first"
    fi
done

mapfile -t PATS < <(devonly_patterns refs/heads/dev refs/heads/main)
((${#PATS[@]})) || die "no dev-only manifest ($DEVONLY_FILE) on dev or main"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# strip_tree <tree-ish>: the tree without the dev-only paths
strip_tree() {
    local idx="$tmp/strip.idx"
    rm -f "$idx"
    GIT_INDEX_FILE=$idx git read-tree "$1"
    devonly_paths "$1" "${PATS[@]}" | GIT_INDEX_FILE=$idx git update-index -z --force-remove --stdin
    GIT_INDEX_FILE=$idx git write-tree
}

# keep_devonly <tree> <from>: <tree> with its dev-only paths replaced by those of <from>
keep_devonly() {
    local idx="$tmp/keep.idx" path
    rm -f "$idx"
    GIT_INDEX_FILE=$idx git read-tree "$1"
    devonly_paths "$1" "${PATS[@]}" | GIT_INDEX_FILE=$idx git update-index -z --force-remove --stdin
    git ls-tree -r -z --full-tree "$2" | while IFS= read -r -d '' entry; do
        path=${entry#*$'\t'}
        devonly_match "$path" "${PATS[@]}" && printf '%s\0' "$entry"
    done | GIT_INDEX_FILE=$idx git update-index -z --index-info
    GIT_INDEX_FILE=$idx git write-tree
}

main_old=$(git rev-parse refs/heads/main)
dev_old=$(git rev-parse refs/heads/dev)
dev_new=$dev_old
dev_tree=$(git rev-parse "$dev_old^{tree}")
backsync=""

# 1. back-sync main into dev, when main has something dev lacks. Commits that are already on dev as
# cherry-picks (same patch) count as present; a three-way merge of them could conflict for no reason.
main_only=$(git cherry "$dev_old" "$main_old" | grep -c '^+' || true)
if git merge-base --is-ancestor "$main_old" "$dev_old"; then
    :
elif ((main_only == 0)); then
    echo "Back-sync not needed: main's own commits are already on dev as cherry-picks."
else
    set +e
    out=$(git merge-tree --write-tree --name-only --no-messages "$dev_old" "$main_old")
    rc=$?
    set -e
    ((rc <= 1)) || die "git merge-tree failed: $out"
    merged=$(head -n1 <<<"$out")
    if ((rc == 1)); then
        bad=()
        while IFS= read -r p; do
            [[ -n $p ]] && ! devonly_match "$p" "${PATS[@]}" && bad+=("$p")
        done < <(tail -n +2 <<<"$out")
        if ((${#bad[@]})); then
            printf 'merge-dev: main and dev conflict outside the dev-only paths:\n' >&2
            printf '  %s\n' "${bad[@]}" >&2
            die "resolve by merging main into dev by hand in a separate worktree, keeping $DEVONLY_FILE paths, then rerun"
        fi
    fi
    synced=$(keep_devonly "$merged" "$dev_old")
    if [[ $synced != "$dev_tree" ]]; then
        backsync=$(git commit-tree "$synced" -p "$dev_old" -p "$main_old" \
            -m "Merge main into dev" -m "Brings the commits made directly on main into dev; dev-only paths ($DEVONLY_FILE) kept.")
        echo "Back-sync: main has changes dev lacks. These files change in the working tree:"
        git diff --stat "$dev_old" "$backsync" | sed 's/^/  /'
        dev_new=$backsync
        dev_tree=$synced
    fi
fi

# 2. forward merge: main becomes dev's tree minus the dev-only paths
new_tree=$(strip_tree "$dev_tree")
if [[ $new_tree == "$(git rev-parse "$main_old^{tree}")" ]]; then
    echo "main already matches dev (minus dev-only paths); nothing to merge."
    new_main=""
else
    new_main=$(git commit-tree "$new_tree" -p "$main_old" -p "$dev_new" \
        -m "Merge dev into main" -m "Dev-only paths left out ($DEVONLY_FILE): ${PATS[*]}")
    echo "Forward merge: main ${main_old:0:12} -> ${new_main:0:12}"
    git diff --stat "$main_old" "$new_main" | sed 's/^/  /'
    bash .github/scripts/guard.sh "$new_main" "$dev_new"
fi

if ((DRY)); then
    echo "Dry run: no branch was changed."
    exit 0
fi

if [[ -n $backsync ]]; then
    git merge --ff-only --quiet "$backsync"
    echo "dev fast-forwarded to ${backsync:0:12}."
fi
if [[ -n $new_main ]]; then
    git update-ref -m "merge-dev: merge dev into main" refs/heads/main "$new_main" "$main_old"
    echo "main updated to ${new_main:0:12}."
fi

if ((PUSH)); then
    # dev first, whenever it is ahead of origin: the main workflow recognises a merge of reviewed dev
    # commits only once they are on origin/dev
    if [[ $(git rev-parse refs/heads/dev) != "$(git rev-parse --verify --quiet refs/remotes/origin/dev || true)" ]]; then
        git push origin dev
    fi
    if [[ $(git rev-parse refs/heads/main) != "$(git rev-parse --verify --quiet refs/remotes/origin/main || true)" ]]; then
        git push origin main
    fi
fi
echo "Done. main and dev now differ only by: ${PATS[*]}"
