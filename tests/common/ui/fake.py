#!/usr/bin/env python3
"""A stand-in for a program the shell launches (linked under that program's name in RUNDIR/fakebin): logs the call to
RUNDIR/commands.log as "RUN <name> <args as JSON>", prints RUNDIR/fake/<name>.out if it exists and exits with the code
in RUNDIR/fake/<name>.code (0 without one). Nothing else happens. Refuses to run outside a test sandbox."""
import json
import os
import sys
from pathlib import Path

run = os.environ.get("SLEEPYSHELL_SANDBOX")
if not run:
    sys.exit("fake: only inside a test sandbox")
name = Path(sys.argv[0]).name
with open(Path(run) / "commands.log", "a") as f:
    f.write(f"RUN {name} {json.dumps(sys.argv[1:])}\n")
out = Path(run) / "fake" / f"{name}.out"
if out.exists():
    sys.stdout.write(out.read_text())
code = Path(run) / "fake" / f"{name}.code"
sys.exit(int(code.read_text().strip()) if code.exists() else 0)
