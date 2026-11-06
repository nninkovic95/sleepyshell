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

# the keybinds file of the Keybinds tab: missing, empty, Sleepysettings' own, and the user's own file (asked first)
K=$D/k
mkdir -p "$K"
printf 'new\n' | run w-missing python3 -I "$HC" write-binds "$K/sub/new.lua"
: >"$K/empty.lua"
printf 'into empty\n' | run w-empty python3 -I "$HC" write-binds "$K/empty.lua"
printf -- '-- Keybinds added in Sleepysettings: managed\nold line\n' >"$K/own.lua"
printf -- '-- Keybinds added in Sleepysettings: managed\nnew line\n' | run w-own python3 -I "$HC" write-binds "$K/own.lua"
printf 'my own bind\n' >"$K/foreign.lua"
printf 'my own bind\nadded bind\n' | run w-foreign python3 -I "$HC" write-binds "$K/foreign.lua"
printf 'my own bind\nadded bind\n' | run w-wrongsha python3 -I "$HC" write-binds "$K/foreign.lua" --confirmed 0000
SHA=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha"])' "$D/w-foreign.out" 2>/dev/null)
cp "$K/foreign.lua" "$D/foreign-before.lua"
printf 'my own bind\nadded bind\n' | run w-confirmed python3 -I "$HC" write-binds "$K/foreign.lua" --confirmed "$SHA"

# the window's side: Keybinds.exportTo through the real process, offscreen
mkdir -p "$D/ex"
printf 'mine\n' >"$D/ex/existing.lua"
EXPORT_DIR=$D/ex QT_QPA_PLATFORM=offscreen timeout 40 qs -p "$S/export-harness.qml" >"$D/harness.log" 2>&1
ls -a "$D/ex" >"$D/ex-ls.txt"

# the window's side of Apply: the copy's keybinds file is a file the user wrote
mkdir -p "$D/kb"
printf 'hl.bind("SUPER + F8", hl.dsp.exec_cmd("mine"))\n' >"$D/kb/foreign.lua"
cp "$D/kb/foreign.lua" "$D/kb-before.lua"
printf '[files]\npathCustombinds = "%s"\n' "$D/kb/foreign.lua" >"$S/sleepysettings.toml"
QT_QPA_PLATFORM=offscreen timeout 40 qs -p "$S/binds-harness.qml" >"$D/binds.log" 2>&1
rm -f "$S/sleepysettings.toml"
