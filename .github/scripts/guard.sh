#!/usr/bin/env bash
# guard.sh <ref> [manifest-ref...]: fail when any dev-only path (.github/dev-only) exists in <ref>'s tree.
# The manifest is read from <ref> and from every extra ref given (CI passes origin/dev), so removing an
# entry on one branch does not open a hole. No manifest anywhere is an error, not a pass.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
# shellcheck source=devonly.sh
source "$here/devonly.sh"

ref=${1:?usage: guard.sh <ref> [manifest-ref...]}
shift
commit=$(git rev-parse --verify --quiet --end-of-options "$ref^{commit}") || {
    echo "guard: no such commit: $ref" >&2
    exit 2
}

mapfile -t pats < <(devonly_patterns "$commit" "$@")
if ((${#pats[@]} == 0)); then
    echo "guard: no dev-only manifest ($DEVONLY_FILE) found in $ref${*:+ or $*}" >&2
    exit 2
fi

mapfile -d '' -t leaks < <(devonly_paths "$commit" "${pats[@]}")
if ((${#leaks[@]})); then
    echo "guard: dev-only content found in $ref (${commit:0:12}):" >&2
    printf '  %s\n' "${leaks[@]}" >&2
    if [[ -n ${GITHUB_ACTIONS:-} ]]; then
        printf '::error title=Dev-only content on %s::%s dev-only file(s), first: %s\n' \
            "$ref" "${#leaks[@]}" "${leaks[0]}"
    fi
    exit 1
fi
echo "guard: ${commit:0:12} holds no dev-only paths (${pats[*]})"
