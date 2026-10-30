#!/bin/bash
# compile.sh TREE: compile every .qml file of a sleepyshell tree, without creating anything.
#
# The tree is copied into a run folder (with an empty sleepysettings.toml of its own) and its shell.qml
# is replaced by a root that imports every module folder and calls Qt.createComponent on each file.
# A module the root does not import is not built at all, so every folder is imported, or the settings
# window's and the lock's files would fail for that reason alone. The real shell.qml is compiled under
# another name. Components are compiled, never instantiated (the lock does not lock), and the whole
# check runs in the kit's sandbox, so even a mistake here cannot write anything real.
# Prints one line per failing file and "compile: N files, K failed"; exits 1 when K > 0.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/env.sh"
SRC=$(readlink -f "${1:?tree}")
[ -f "$SRC/shell.qml" ] || { echo "compile: $SRC is not a sleepyshell tree"; exit 2; }
D=$RUN/compile-$$
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT
mkdir -p "$D"
copy_tree "$SRC" "$D/tree"
rm -f "$D"/tree/sleepysettings.toml* "$D"/tree/settings.json*
: > "$D/tree/sleepysettings.toml"

python3 -I - "$D/tree" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
(d / "entry-shell.qml").write_text((d / "shell.qml").read_text())
files = sorted(str(p.relative_to(d)) for p in d.rglob("*.qml") if p != d / "shell.qml")
mods = sorted({p.parent for p in d.rglob("*.qml")} - {d})
imports = "\n".join("import qs." + ".".join(m.relative_to(d).parts) for m in mods)
names = ",\n".join('"%s"' % f for f in files)
(d / "shell.qml").write_text(f'''import QtQuick
import Quickshell
import qs
{imports}

ShellRoot {{
    Component.onCompleted: {{
        const files = [{names}];
        let bad = 0;
        for (const f of files) {{
            const c = Qt.createComponent(Qt.resolvedUrl(f));
            if (c.status !== Component.Ready) {{
                bad++;
                console.log("COMPILE FAIL " + f + ": " + c.errorString().trim());
            }}
        }}
        console.log("COMPILE DONE " + files.length + " " + bad);
        Qt.quit();
    }}
}}
''')
PY

out=$(timeout 40 bash "$KIT/common/sandbox.sh" "$D" qs -p "$D/tree" 2>&1 | grep -aE "COMPILE (FAIL|DONE)|ERROR" || true)
echo "$out" | grep -E "COMPILE FAIL|ERROR" | sed 's/.*COMPILE FAIL /fail: /; s/.*ERROR[^:]*: /error: /' || true
done=$(echo "$out" | grep -oE "COMPILE DONE [0-9]+ [0-9]+" | tail -1)
if [ -z "$done" ]; then
    echo "compile: the check did not finish (the root itself failed to load)"
    exit 1
fi
set -- $done
echo "compile: $3 files, $4 failed"
[ "$4" -eq 0 ]
