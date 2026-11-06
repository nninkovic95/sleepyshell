"""prepare.py TREE: make a run copy drivable by whole-window tests. Only ever run on a copy under the run folder.

Quickshell's Scope and ShellRoot do not let script walk their children, and there is no list of windows, so:
  - every window declaration (PanelWindow, FloatingWindow, PopupWindow, WlSessionLockSurface) gets an id where it has
    none and one child `QtObject` that adds the window to SleepytestRegistry (a singleton written into the copy) when
    it is created and removes it when it goes;
  - files outside the copy's root that use the registry get `import qs`.
With --pam DIR the lock's PamContext also reads its PAM stack from DIR instead of /etc/pam.d (ui.pam_stack writes a
test stack there that knows only a test password), so a lock test never asks the account's own PAM or pam_faillock.
Nothing else in the copy changes; the entry files get the driver later (inject.py). Running it twice changes nothing."""
import re
import sys
from pathlib import Path

WINDOW = re.compile(r"^(\s*)(PanelWindow|FloatingWindow|PopupWindow|WlSessionLockSurface)\s*\{\s*$")
REGISTRY = """pragma Singleton
// Test registry (added to a test's run copy only): the windows that exist now, for the test driver.
import QtQuick
import Quickshell

Singleton {
    property var wins: []
    function add(w) {
        if (!wins.includes(w))
            wins = wins.concat([w]);
    }
    function remove(w) {
        wins = wins.filter(x => x !== w);
    }
}
"""


def patch(path, root, counter):
    lines = path.read_text().splitlines()
    out, changed, i = [], False, 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = WINDOW.match(line)
        if m and "sleepytest" not in "".join(lines[i + 1:i + 3]):
            indent, child = m.group(1), m.group(1) + "    "
            wid = None
            for nxt in lines[i + 1:]:
                if nxt.strip() == "}" and len(nxt) - len(nxt.lstrip()) <= len(indent):
                    break
                im = re.match("^" + re.escape(child) + r"id:\s*(\w+)\s*$", nxt)
                if im:
                    wid = im.group(1)
                    break
            if wid is None:
                counter[0] += 1
                wid = f"sleepytestWin{counter[0]}"
                out.append(f"{child}id: {wid}")
            out.append(f"{child}QtObject {{ Component.onCompleted: SleepytestRegistry.add({wid}); "
                       f"Component.onDestruction: SleepytestRegistry.remove({wid}) }}")
            changed = True
        i += 1
    if not changed:
        return False
    if path.parent != root and not any(l.strip() == "import qs" for l in out):
        last = max(k for k, l in enumerate(out) if l.startswith("import "))
        out.insert(last + 1, "import qs")
    path.write_text("\n".join(out) + "\n")
    return True


def use_pam_dir(root, pam_dir):
    lock = root / "sleepylock" / "Sleepylock.qml"
    t = lock.read_text()
    old = '        config: "login"\n'
    if old not in t:
        sys.exit("prepare: the lock's PamContext no longer has config: \"login\"; update prepare.py")
    lock.write_text(t.replace(old, old + f'        configDirectory: "{pam_dir}"\n', 1))


def main():
    root = Path(sys.argv[1]).resolve()
    if "--pam" in sys.argv:
        pam_marker = root / ".sleepytest-pam"
        if not pam_marker.exists():
            use_pam_dir(root, Path(sys.argv[sys.argv.index("--pam") + 1]).resolve())
            pam_marker.write_text("")
    marker = root / ".sleepytest-prepared"
    if marker.exists():
        return
    (root / "SleepytestRegistry.qml").write_text(REGISTRY)
    counter = [0]
    n = sum(patch(p, root, counter) for p in sorted(root.rglob("*.qml")) if not p.name.startswith(("sleepytest", "Sleepytest")))
    marker.write_text(f"{n} files\n")


if __name__ == "__main__":
    main()
