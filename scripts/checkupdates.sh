#!/bin/sh
# Pending updates without root and without pacman-contrib: sync the repo databases into a
# private copy (what checkupdates does), then list repo and AUR upgrades.
# Output: one line "REPO <n>", "AUR <n>", then one "PKG <name> <old> -> <new>" line per package.
db="${XDG_RUNTIME_DIR:-/tmp}/sleepyshell-checkupdates"
mkdir -p "$db"
[ -e "$db/local" ] || ln -s /var/lib/pacman/local "$db/local"
fakeroot -- pacman -Sy --dbpath "$db" --logfile /dev/null --disable-sandbox >/dev/null 2>&1 || exit 1
repo=$(pacman -Qu --dbpath "$db" 2>/dev/null | grep -v '\[ignored\]')
aur=$(paru -Qua 2>/dev/null | grep -v '\[ignored\]')
echo "REPO $(printf '%s' "$repo" | grep -c .)"
echo "AUR $(printf '%s' "$aur" | grep -c .)"
printf '%s\n' "$repo" "$aur" | grep . | sed 's/^/PKG /'
