#!/bin/bash
# settings/ask-first-writers.test.sh [TREE]: the two writers of files the user owns that must ask first.
#
# Tier 2 (a user's file changed without a yes): the Keybinds tab's Export replaced a file that already existed, and its
# Apply edited a keybinds file the user pointed it at, with no
# question and no backup; the matugen folder-icon confirmation showed three sample lines, not what was added. In one
# sandbox: hyprconf.py export-binds creates a new file, refuses an existing one without --replace (exit 3, untouched),
# replaces it with --replace after a backup, writes through a link, refuses a folder and a relative path; the window's
# export (Keybinds.exportTo, offscreen) goes through that script, names the existing file for the question and writes
# it only with the yes. appearance.py folders-state returns the whole block with its hash; folders-setup writes
# nothing when the hash is not the shown block's (exit 6) and writes exactly that block when it is, after a backup.
# The questions themselves are checked in the real window: export-asks, ask-first-prompts and ask-first-config.
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=ask-first-writers-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
copy_tree "$TREE" "$D/s"
rm -f "$D"/s/sleepysettings.toml* "$D"/s/settings.json*
cp "$KIT/settings/export-harness.qml" "$KIT/settings/binds-harness.qml" "$D/s/"

timeout 150 bash "$KIT/common/sandbox.sh" "$D" bash "$KIT/settings/ask-first-writers-inner.sh" "$D"

python3 -I - "$D" <<'CHECK_ASK_FIRST_PY'
import json, sys
from pathlib import Path
D = Path(sys.argv[1])
X = D / "x"
fails = 0
def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else f": {detail}"))
    fails += 0 if ok else 1
codes = dict(l.split() for l in (D / "cases.txt").read_text().splitlines()) if (D / "cases.txt").exists() else {}
def out(case):
    f = D / f"{case}.out"
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        return None
def read(p):
    return p.read_text() if p.exists() else None
def body(t):
    # the export's header carries the minute it was made; the rest must match exactly
    return None if t is None else "\n".join(l for l in t.splitlines() if not l.startswith("-- exported "))
baks = lambda folder, name: sorted(p for p in folder.iterdir() if p.name.startswith(name + ".bak-"))

check(codes.get("e-new") == "0" and read(X / "new.lua") == "first\n" and not baks(X, "new.lua"),
      "export creates a new file with the text, no backup", f"exit {codes.get('e-new')}")
r = out("e-exists")
check(codes.get("e-exists") == "3" and r and r["exists"] and not r["ok"], "export refuses an existing file without --replace (exit 3)", f"exit {codes.get('e-exists')}, {r}")
b = baks(X, "kept.lua")
check(read(X / "kept.lua") == "third\n" and len(b) == 1 and b[0].read_text() == "old\n",
      "with --replace the file is replaced after one backup holding the old text", f"{read(X / 'kept.lua')!r}, backups {[p.name for p in b]}")
check(codes.get("e-replace") == "0" and (out("e-replace") or {}).get("backup", "").endswith(b[0].name if b else "?"),
      "the answer names the backup", f"{out('e-replace')}")
check((X / "link.lua").is_symlink() and read(X / "real.lua") == "through\n", "a link is written through, the link stays")
check(codes.get("e-folder") == "1" and (X / "afolder.lua").is_dir(), "a folder at the path is refused", f"exit {codes.get('e-folder')}")
check(codes.get("e-relative") == "1", "a relative path is refused", f"exit {codes.get('e-relative')}")
check(not [p for p in X.iterdir() if ".tmp-" in p.name], "no temporary file left")

st = out("m-state")
templates = (st or {}).get("templates", [])
block = (st or {}).get("block", "")
check(st is not None and templates and all(f"sleepy_folder_{t.replace('-', '_')}" in block for t in templates)
      and block.count("output_path") == len(templates),
      "folders-state returns the whole block, every entry", f"{len(templates)} templates, block {len(block)} chars")
check(codes.get("m-wrong") == "6" and read(D / "matugen-after-wrong.toml") == read(D / "matugen-before.toml"),
      "folders-setup with another hash writes nothing (exit 6)", f"exit {codes.get('m-wrong')}")
after = read(D / "matugen.toml") or ""
mb = baks(D, "matugen.toml")
check(codes.get("m-right") == "0" and block and block in after and after.startswith("[config]\n"),
      "folders-setup with the shown hash adds exactly the shown block", f"exit {codes.get('m-right')}")
check(len(mb) == 1 and mb[0].read_text() == "[config]\n", "the matugen config was backed up first", f"{[p.name for p in mb]}")

K = D / "k"
HEAD = "-- Keybinds added in Sleepysettings"
check(codes.get("w-missing") == "0" and read(K / "sub/new.lua") == "new\n", "write-binds creates a missing file and its folder", f"exit {codes.get('w-missing')}")
check(codes.get("w-empty") == "0" and read(K / "empty.lua") == "into empty\n" and not baks(K, "empty.lua"),
      "an empty file is written without a question", f"exit {codes.get('w-empty')}")
ob = baks(K, "own.lua")
check(codes.get("w-own") == "0" and "new line" in (read(K / "own.lua") or "") and len(ob) == 1 and "old line" in ob[0].read_text(),
      "Sleepysettings' own file is written after a backup", f"exit {codes.get('w-own')}, backups {[p.name for p in ob]}")
wf = out("w-foreign") or {}
check(codes.get("w-foreign") == "3" and wf.get("foreign") and "added bind" in wf.get("added", []) and wf.get("sha"),
      "the user's own file is refused without the yes, with the lines it would add", f"exit {codes.get('w-foreign')}, {wf}")
check(codes.get("w-wrongsha") == "3" and read(D / "foreign-before.lua") == "my own bind\n",
      "a yes for another change writes nothing", f"exit {codes.get('w-wrongsha')}")
fb = baks(K, "foreign.lua")
after = read(K / "foreign.lua") or ""
check(codes.get("w-confirmed") == "0" and after.startswith(HEAD) and after.endswith("my own bind\nadded bind\n")
      and len(fb) == 1 and fb[0].read_text() == "my own bind\n",
      "with the yes it gets the header and the change, after a backup", f"exit {codes.get('w-confirmed')}, {after[:80]!r}")

blog = (D / "binds.log").read_text(errors="replace") if (D / "binds.log").exists() else ""
bline = next((l for l in blog.splitlines() if "RESULT {" in l), None)
b = json.loads(bline[bline.index("RESULT {") + 7:]) if bline else None
kb = D / "kb"
check(b is not None and b["addError"] == "" and b["ask"] is not None and b["stagedAfterAsk"],
      "the tab's Apply onto the user's file stops at the question, the draft kept", "\n".join(blog.splitlines()[-12:]) if not b else f"{b}")
if b and b["ask"]:
    check(any("SUPER + F9" in l for l in b["ask"]["added"]), "the question lists the added bind", f"{b['ask']}")
    kafter = read(kb / "foreign.lua") or ""
    kb_b = baks(kb, "foreign.lua")
    check(kafter.startswith(HEAD) and "SUPER + F8" in kafter and "SUPER + F9" in kafter and not b["stagedAfterYes"] and b["writeError"] == ""
          and len(kb_b) == 1 and kb_b[0].read_text() == read(D / "kb-before.lua"),
          "after the yes the file keeps its own bind, gains the new one and the header, the old text is backed up",
          f"{kafter[:200]!r}, backups {[p.name for p in kb_b]}, {b}")

# Export hands a new name back without making the file: the writer creates it, so a new name is never asked about
kq = (D / "s/services/Keybinds.qml").read_text()
fbq = (D / "s/sleepysettings/components/FolderBrowser.qml").read_text()
check("create: false" in kq and "createOnPick" in fbq and "fb.createOnPick ||" in fbq,
      "the export browser does not pre-create a new file")

log = (D / "harness.log").read_text(errors="replace") if (D / "harness.log").exists() else ""
line = next((l for l in log.splitlines() if "RESULT {" in l), None)
h = json.loads(line[line.index("RESULT {") + 7:]) if line else None
steps = {s["step"]: s for s in (h or {}).get("steps", [])}
ex = D / "ex"
check(h is not None and len(steps) == 3, "the window's export ran all three steps", "\n".join(log.splitlines()[-12:]))
if h:
    check(body(read(ex / "new.lua")) == body(h["text"]) and h["text"] != "", "the window's export writes the whole text through stdin",
          f"{len(read(ex / 'new.lua') or '')} of {len(h['text'])} chars")
    s2 = steps.get(2, {})
    check(s2.get("ask", "").endswith("/existing.lua") and not s2.get("failed"), "an existing file is named for the question, not written",
          f"{s2}")
    check(body(read(ex / "existing.lua")) == body(h["text"]) and [p.read_text() for p in baks(ex, "existing.lua")] == ["mine\n"],
          "after the yes it is replaced, the old text kept as a backup", f"{steps.get(3)}")
sys.exit(1 if fails else 0)
CHECK_ASK_FIRST_PY
rc=$?

if python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null; then
    echo "PASS no real file changed"
else
    echo "FAIL a real file changed:"
    python3 -I "$KIT/common/guard.py" verify "$NAME" | sed 's/^/    /'
    rc=1
fi
trap - EXIT
bash "$KIT/common/cleanup.sh" "$D" >/dev/null && echo "PASS nothing left running, run folder deleted" || { echo "FAIL processes, windows or files left"; rc=1; }
exit $rc
