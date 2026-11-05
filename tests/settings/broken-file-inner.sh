#!/bin/bash
# The sandboxed half of settings/broken-file.sh: runs inside common/sandbox.sh, never on its own.
# broken-file-inner.sh RUN_FOLDER
# Every outside program the scripts would run (notify-send, matugen, awww, swww, magick, gsettings) is a stub on
# PATH that logs its call to calls-<case>.log. Writes one line per case to cases.txt: "<case> <exit code>".
set -uo pipefail
D=$1
S=$D/s
mkdir -p "$D/bin" "$D/walls" "$XDG_CONFIG_HOME/hypr" "$D/proc" "$D/power"
for p in notify-send matugen awww swww magick gsettings; do
    printf '#!/bin/sh\necho "%s $*" >> "$T3_CALLS"\nexit 0\n' "$p" >"$D/bin/$p"
    chmod +x "$D/bin/$p"
done
export PATH="$D/bin:$PATH"
export SLEEPYSHELL_HYPRIDLE_SERVICE=none SLEEPYSHELL_HYPRIDLE_PROC=$D/proc SLEEPYSHELL_POWER_SUPPLY=$D/power
export THEME_MATUGEN_CONFIG=$D/matugen.toml APPEARANCE_GSETTINGS=$D/bin/gsettings
cp "$D/pic.png" "$D/walls/a.png"
CONF=$XDG_CONFIG_HOME/hypr/hypridle.conf
: > "$D/cases.txt"

# run CASE SETTINGS CMD...: the command with that settings file, its exit code to cases.txt, its output to <case>.out
run() {
    local name=$1 file=$2
    shift 2
    T3_CALLS=$D/calls-$name.log SLEEPYSHELL_SETTINGS=$file THEME_SETTINGS=$file "$@" >"$D/$name.out" 2>"$D/$name.err"
    echo "$name $?" >>"$D/cases.txt"
    touch "$D/calls-$name.log"
}

# the shell's own hypridle.conf, from valid settings, as idle.py would have written it before the file broke
SLEEPYSHELL_SETTINGS=$D/good.toml python3 -I "$S/scripts/idle.py" --print --ac >"$CONF"
sha256sum "$CONF" >"$D/conf-before.sha"

run idle-apply "$D/bad.toml" python3 -I "$S/scripts/idle.py" --ac
run idle-background "$D/bad.toml" python3 -I "$S/scripts/idle.py" --background --battery
run idle-print "$D/bad.toml" python3 -I "$S/scripts/idle.py" --print --ac
run idle-find "$D/bad.toml" python3 -I "$S/scripts/idle.py" --find
sha256sum "$CONF" >"$D/conf-after-bad.sha"
run idle-good "$D/good.toml" python3 -I "$S/scripts/idle.py" --ac
cp "$CONF" "$D/conf-after-good"

run theme-auto "$D/bad.toml" python3 -I "$S/scripts/theme.py" --auto
run theme-pick "$D/bad.toml" python3 -I "$S/scripts/theme.py" "$D/walls/a.png"
run theme-preset "$D/bad.toml" python3 -I "$S/scripts/theme.py" --preset ayu
run theme-list "$D/bad.toml" python3 -I "$S/scripts/theme.py" --list-presets
run theme-good "$D/good.toml" python3 -I "$S/scripts/theme.py" --auto
run appearance "$D/bad.toml" python3 -I "$S/scripts/appearance.py" apply colorScheme --color-scheme dark

# the bar's side: the harness in a copy whose own settings file is broken, its idle.py a stub that only logs
cp "$D/bad.toml" "$S/sleepysettings.toml"
mv "$S/scripts/idle.py" "$S/scripts/idle.py.real"
printf '#!/bin/sh\necho "idle.py $*" >> "%s"\n' "$D/calls-bar.log" >"$S/scripts/idle.py"
chmod +x "$S/scripts/idle.py"
T3_CALLS=$D/calls-bar.log QT_QPA_PLATFORM=offscreen timeout 30 qs -p "$S/broken-harness.qml" >"$D/bar.log" 2>&1
touch "$D/calls-bar.log"
