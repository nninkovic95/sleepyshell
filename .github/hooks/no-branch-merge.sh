#!/usr/bin/env bash
# Shared by the pre-merge-commit and pre-commit hooks: refuses a hand-made merge of dev into main or of
# main into dev. Those merges go through tools/merge-dev.sh, which builds its commits with plumbing
# (merge-tree, commit-tree, update-ref) and so never runs these hooks.
set -euo pipefail
gitdir=$(git rev-parse --git-dir)
branch=$(git symbolic-ref --quiet --short HEAD || true)
case $branch in
main) other=dev ;;
dev) other=main ;;
*) exit 0 ;;
esac

# What is being merged: MERGE_HEAD when a conflicted merge is concluded with "git commit"; during
# pre-merge-commit git has not written MERGE_HEAD yet, and only GIT_REFLOG_ACTION ("merge <names>") says.
heads=()
if [[ -f $gitdir/MERGE_HEAD ]]; then
    mapfile -t heads <"$gitdir/MERGE_HEAD"
elif [[ ${GIT_REFLOG_ACTION:-} == merge\ * ]]; then
    read -r -a words <<<"${GIT_REFLOG_ACTION#merge }"
    for w in "${words[@]}"; do
        [[ $w == -* ]] && continue
        sha=$(git rev-parse --verify --quiet --end-of-options "$w^{commit}") && heads+=("$sha")
    done
fi
((${#heads[@]})) || exit 0

refs=()
for r in "refs/heads/$other" "refs/remotes/origin/$other"; do
    git rev-parse --verify --quiet "$r" >/dev/null && refs+=("$r")
done

for sha in "${heads[@]}"; do
    [[ -n $sha ]] || continue
    for r in "${refs[@]}"; do
        if git merge-base --is-ancestor "$sha" "$r"; then
            echo "Refusing a hand-made merge of $other into $branch: it would carry or delete the dev-only" >&2
            echo "paths in .github/dev-only. Abort it (git merge --abort) and run tools/merge-dev.sh instead." >&2
            exit 1
        fi
    done
done
