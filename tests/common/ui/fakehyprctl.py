#!/usr/bin/env python3
"""A stand-in for hyprctl inside a test sandbox: sends the request to the stand-in Hyprland (fakehypr.py) and prints
its answer, so a script under test sees the test's monitors and workspaces and every dispatch is logged there.
Refuses to run outside a test sandbox."""
import os
import socket
import sys

if not os.environ.get("SLEEPYSHELL_SANDBOX"):
    sys.exit("hyprctl (test stand-in): only inside a test sandbox")
args = [a for a in sys.argv[1:] if a not in ("-j", "--json")]
json_flag = len(args) != len(sys.argv) - 1
if not args:
    sys.exit("usage: hyprctl [-j] COMMAND [ARGS]")
req = ("j/" if json_flag else "") + " ".join(args)
path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), ".socket.sock")
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(path)
except OSError:
    sys.exit("HYPRLAND_INSTANCE_SIGNATURE invalid or no compositor")
s.sendall(req.encode())
out = b""
while chunk := s.recv(65536):
    out += chunk
sys.stdout.write(out.decode(errors="replace") + ("\n" if not out.endswith(b"\n") else ""))
sys.exit(1 if out.startswith(b"unknown request") else 0)
