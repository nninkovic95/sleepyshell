#!/bin/bash
# lock/pam-timeout.sh [TREE]: the lock screen's password check gives up on a hang, and Escape never changes what is
# checked.
#
# Tier 1 (the lock): a PAM module that never answered left the lock's field read-only for good, with no way to try
# again; and Escape during a check emptied the text that PAM was then answered with (an empty password counts as a
# failed attempt). The tree's (default: the live shell's) real Sleepylock.qml runs offscreen in the sandbox and is
# never locked (its run copy gets two aliases the harness needs); its PamContext uses test PAM stacks in the run folder (pam_permit, pam_exec), never the system's, so
# no real password is checked and pam_faillock is never involved. The check timeout is shortened to 3 s for the run;
# the harness reports the tree's own value, which must be 30 s. (The polkit prompt's timeout and Escape need a real
# polkit agent: checked by hand on the live session.)
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=pam-timeout-$$
D=$RUN/$NAME
mkdir -p "$D/pam"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
copy_tree "$TREE" "$D/s"
rm -f "$D"/s/sleepysettings.toml* "$D"/s/settings.json*
cp "$KIT/lock/pam-harness.qml" "$D/s/"
# Quickshell's Scope keeps its children where QML cannot reach them, so this run's copy of the lock (never the real
# file) gets two aliases for the harness: its PamContext and, where the tree has it, its check timeout
python3 -I - "$D/s/sleepylock/Sleepylock.qml" <<'ADD_TEST_ALIASES_PY'
import sys
p = sys.argv[1]
s = open(p).read()
extra = "    property alias testPam: pam\n"
if "id: checkTimeout" in s:
    extra += "    property alias testTimeout: checkTimeout\n"
s = s.replace("    id: root\n", "    id: root\n" + extra, 1)
open(p, "w").write(s)
ADD_TEST_ALIASES_PY
printf '#!/bin/sh\nexec sleep 120\n' >"$D/hang.sh"
printf '#!/bin/sh\ntr -d "\\000" > "%s/got"\nexit 1\n' "$D" >"$D/record.sh"
chmod +x "$D/hang.sh" "$D/record.sh"
printf 'auth required pam_permit.so\naccount required pam_permit.so\n' >"$D/pam/permit"
printf 'auth required pam_exec.so expose_authtok %s/record.sh\naccount required pam_permit.so\n' "$D" >"$D/pam/record"
printf 'auth required pam_exec.so %s/hang.sh\naccount required pam_permit.so\n' "$D" >"$D/pam/hang"

timeout 90 bash "$KIT/common/sandbox.sh" "$D" sh -c 'QT_QPA_PLATFORM=offscreen T3_PAM="$1/pam" timeout 60 qs -p "$1/s/pam-harness.qml" >"$1/qs.log" 2>&1' sh "$D"

python3 -I - "$D" <<'CHECK_PAM_TIMEOUT_PY'
import json, sys
from pathlib import Path
D = Path(sys.argv[1])
fails = 0
def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else f": {detail}"))
    fails += 0 if ok else 1
log = (D / "qs.log").read_text(errors="replace") if (D / "qs.log").exists() else ""
line = next((l for l in log.splitlines() if "RESULT {" in l), None)
if line is None:
    check(False, "the harness reported", "\n".join(log.splitlines()[-15:]))
    sys.exit(1)
r = json.loads(line[line.index("RESULT {") + 7:])
if "error" in r:
    check(False, "the harness found the lock's PAM conversation", r["error"])
    sys.exit(1)
p = r["permit"]
check(p["completions"] == ["success"] and not p["inProgress"] and not p["failure"], "a check that PAM accepts succeeds (control)", f"{p}")
got = (D / "got").read_text() if (D / "got").exists() else None
check(got == "secret1", "Escape during a check does not change what PAM is answered with", f"PAM got {got!r}")
rec = r["record"]
check(not rec["inProgress"] and rec["failure"] and rec["failureText"] == "Wrong password", "a refused check says Wrong password", f"{rec}")
check(r["hangEarly"]["inProgress"], "a hanging check is still running before the timeout", f"{r['hangEarly']}")
hg = r["hang"]
check(not hg["inProgress"] and hg["failure"] and hg["failureText"] == "Took too long, try again" and hg["field"] == ""
      and hg["pamActive"] is False and hg["completions"] == [],
      "a hanging check is given up, the face says it took too long, the conversation is ended", f"{hg}")
rt = r["retry"]
check(rt["completions"] == ["success"] and not rt["inProgress"], "a new check works after one was given up", f"{rt}")
check(r.get("timeoutWas") == 30000, "the lock's own timeout is 30 s", f"{r.get('timeoutWas')}")
sys.exit(1 if fails else 0)
CHECK_PAM_TIMEOUT_PY
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
