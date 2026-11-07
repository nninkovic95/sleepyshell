#!/usr/bin/env bash
# default-settings.sh: the settings file the installer ships, rendered from the schema.
#
#   tools/default-settings.sh [--check] [--tree TREE] [--out FILE]
#
# Renders sleepysettings.toml exactly as the shell writes it (services/Settings.qml: one [section] per tab, a comment
# above every key), with every value at its schema default and without the notes that describe this machine (a
# missing program, no battery), so the file is the same on every machine. The output is data/default-settings.toml
# of TREE (default: the folder this script belongs to); install.sh copies it into place when there is no settings file.
# --check writes nothing and exits 1 when the file is out of date (the test kit runs it, inside its sandbox).
# Runs Quickshell offscreen on a scratch copy without any settings file; it reads nothing of the user's.
set -euo pipefail

CHECK=0 TREE="" OUT=""
while [ $# -gt 0 ]; do
    case $1 in
    --check) CHECK=1 ;;
    --tree) TREE=${2:?--tree needs a folder}; shift ;;
    --out) OUT=${2:?--out needs a file}; shift ;;
    -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "default-settings: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
TREE=$(readlink -f "${TREE:-$HERE/..}")
OUT=${OUT:-$TREE/data/default-settings.toml}
command -v qs >/dev/null || { echo "default-settings: qs (Quickshell) is not installed" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
# the shell's own files only: no repository folders, no settings file of any kind
tar -C "$TREE" \
    --exclude=./.git --exclude=./.github --exclude=./tests --exclude=./docs --exclude=./gallery --exclude=./assets \
    --exclude=./tools --exclude='./sleepysettings.toml*' --exclude='./settings.json*' -cf - . | tar -C "$TMP" -xf - --one-top-level=s
cp "$HERE/default-settings.qml" "$TMP/s/"
DEFAULTS_OUT=$TMP/out.toml QT_QPA_PLATFORM=offscreen timeout 60 qs -p "$TMP/s/default-settings.qml" >"$TMP/log" 2>&1 || {
    echo "default-settings: rendering failed:" >&2
    tail -20 "$TMP/log" >&2
    exit 1
}
[ -s "$TMP/out.toml" ] || { echo "default-settings: nothing was rendered" >&2; tail -20 "$TMP/log" >&2; exit 1; }

if [ "$CHECK" = 1 ]; then
    if cmp -s "$TMP/out.toml" "$OUT"; then
        echo "default-settings: $OUT is up to date"
        exit 0
    fi
    echo "default-settings: $OUT is out of date; run tools/default-settings.sh" >&2
    diff -u "$OUT" "$TMP/out.toml" 2>/dev/null | head -40 >&2 || true
    exit 1
fi
mkdir -p "$(dirname "$OUT")"
cp "$TMP/out.toml" "$OUT"
echo "default-settings: wrote $OUT"
