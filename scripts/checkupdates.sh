#!/bin/sh
# Pending updates without root and without pacman-contrib: sync the repo databases into a
# private copy (what checkupdates does), then list repo and AUR upgrades.
# Output: one line "REPO <n>", "AUR <n>", then one "PKG <name> <old> -> <new>" line per package.
# The copy lives in the user's own runtime folder, kept between runs so a sync only fetches what changed.
# Without one, a private folder for this run only: a fixed name in a shared /tmp could be made by another user first.
run="${XDG_RUNTIME_DIR:-}"
if [ -O "$run" ] && [ -d "$run" ]; then
    db="$run/sleepyshell-checkupdates"
    mkdir -p -- "$db"
    [ -O "$db" ] && [ -d "$db" ] && [ ! -L "$db" ] || exit 1
else
    db=$(mktemp -d) || exit 1
    trap 'rm -rf -- "$db"' EXIT
fi
[ -e "$db/local" ] || ln -s /var/lib/pacman/local "$db/local"
fakeroot -- pacman -Sy --dbpath "$db" --logfile /dev/null --disable-sandbox >/dev/null 2>&1 || exit 1
repo=$(pacman -Qu --dbpath "$db" 2>/dev/null | grep -v '\[ignored\]')
aur=$(paru -Qua 2>/dev/null | grep -v '\[ignored\]')
echo "REPO $(printf '%s' "$repo" | grep -c .)"
echo "AUR $(printf '%s' "$aur" | grep -c .)"
printf '%s\n' "$repo" "$aur" | grep . | sed 's/^/PKG /'
