# Sourced by guard.sh and tools/merge-dev.sh: the dev-only manifest (.github/dev-only) and its matching.

DEVONLY_FILE=".github/dev-only"

# devonly_patterns <ref>...: the union of the manifest entries found in each ref (refs without a
# manifest are skipped), one per line, comments and blank lines dropped
devonly_patterns() {
    local ref
    for ref in "$@"; do
        git cat-file -e "$ref:$DEVONLY_FILE" 2>/dev/null || continue
        git show "$ref:$DEVONLY_FILE"
    done | sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' | grep -v '^$' | sort -u || true
}

# devonly_match <path> <pattern>...: true when the path falls under any pattern
devonly_match() {
    local path=$1 pat
    shift
    for pat in "$@"; do
        if [[ $pat == */ ]]; then
            [[ $path == "$pat"* ]] && return 0
        else
            # shellcheck disable=SC2053  # the pattern is a glob on purpose
            [[ $path == $pat || $path == $pat/* ]] && return 0
        fi
    done
    return 1
}

# devonly_paths <tree-ish> <pattern>...: every file of the tree that falls under a pattern, NUL-separated
devonly_paths() {
    local tree=$1 path
    shift
    while IFS= read -r -d '' path; do
        devonly_match "$path" "$@" && printf '%s\0' "$path"
    done < <(git ls-tree -r -z --name-only --full-tree "$tree")
}
