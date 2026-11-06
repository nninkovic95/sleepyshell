"""inject.py ENTRY OUT: write OUT, a copy of the entry file ENTRY with the test driver (driver.qml) added inside its root
object. Only a run copy ever gets OUT; the shell's own files are never changed.

The driver needs the root object's id: the root's own `id:` line (four spaces in) is used, or one is added."""
import re
import sys
from pathlib import Path

entry, out = Path(sys.argv[1]), Path(sys.argv[2])
driver = (Path(__file__).parent / "driver.qml").read_text().splitlines()
src = entry.read_text()
lines = src[:src.rstrip().rfind("}")].splitlines()
root_at = next(i for i, l in enumerate(lines) if re.match(r"^[A-Z]\w* \{", l))
m = next((re.match(r"^    id: (\w+)", l) for l in lines[root_at + 1:] if re.match(r"^    id: \w+", l)), None)
root_id = m.group(1) if m else "sleepytestRoot"
if not m:
    lines.insert(root_at + 1, "    id: sleepytestRoot")
imports = [l for l in driver if l.startswith("import ") and l not in lines]
body = [l.replace("SLEEPYTEST_ROOT", root_id) for l in driver if not l.startswith("import ") and not l.startswith("//")]
lines[root_at:root_at] = imports
out.write_text("\n".join(lines) + "\n" + "\n".join(body) + "\n}\n")
