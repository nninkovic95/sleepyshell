#!/bin/bash
# The sandboxed half of settings/ask-first-writers.sh: runs inside common/sandbox.sh, never on its own.
# ask-first-writers-inner.sh RUN_FOLDER
# Writes one line per case to cases.txt: "<case> <exit code>"; outputs to <case>.out.
set -uo pipefail
D=$1
S=$D/s
X=$D/x
mkdir -p "$X"
export THEME_MATUGEN_CONFIG=$D/matugen.toml
: >"$D/cases.txt"

run() {
    local name=$1
    shift
    "$@" >"$D/$name.out" 2>"$D/$name.err"
    echo "$name $?" >>"$D/cases.txt"
}
HC=$S/scripts/hyprconf.py
AP=$S/scripts/appearance.py

# keybind export: a new file, an existing one without and with --replace, a link, a folder, a relative path
printf 'first\n' | run e-new python3 -I "$HC" export-binds "$X/new.lua"
printf 'old\n' >"$X/kept.lua"
printf 'second\n' | run e-exists python3 -I "$HC" export-binds "$X/kept.lua"
printf 'third\n' | run e-replace python3 -I "$HC" export-binds "$X/kept.lua" --replace
printf 'target\n' >"$X/real.lua"
ln -s real.lua "$X/link.lua"
printf 'through\n' | run e-link python3 -I "$HC" export-binds "$X/link.lua" --replace
mkdir "$X/afolder.lua"
printf 'x\n' | run e-folder python3 -I "$HC" export-binds "$X/afolder.lua" --replace
printf 'x\n' | run e-relative python3 -I "$HC" export-binds "relative.lua"

# matugen folder icons: the state shows the whole block; setup writes only the block that was shown
printf '[config]\n' >"$D/matugen.toml"
run m-state python3 -I "$AP" folders-state
cp "$D/matugen.toml" "$D/matugen-before.toml"
run m-wrong python3 -I "$AP" folders-setup --expect 0000
cp "$D/matugen.toml" "$D/matugen-after-wrong.toml"
SHA=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["blockSha"])' "$D/m-state.out" 2>/dev/null)
run m-right python3 -I "$AP" folders-setup --expect "$SHA"
ls "$D" >"$D/ls-after.txt"

# the window's side: Keybinds.exportTo through the real process, offscreen
mkdir -p "$D/ex"
printf 'mine\n' >"$D/ex/existing.lua"
EXPORT_DIR=$D/ex QT_QPA_PLATFORM=offscreen timeout 40 qs -p "$S/export-harness.qml" >"$D/harness.log" 2>&1
ls -a "$D/ex" >"$D/ex-ls.txt"
