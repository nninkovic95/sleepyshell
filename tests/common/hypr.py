#!/usr/bin/env python3
"""hypr.py REQUEST: send one request to Hyprland's command socket and print the reply.

  hypr.py j/clients     hypr.py j/monitors     hypr.py j/version

`hyprctl` does not work inside the kit's sandbox: it finds the compositor through its process id, which
the sandbox's own process namespace cannot see. That is welcome (shell code under test cannot reach the
real compositor through hyprctl), and the kit asks the socket directly with this script instead. Only
reading requests are allowed here ("j/" plus a query word); a test never dispatches."""
import os
import socket
import sys

READ_ONLY = {"clients", "monitors", "workspaces", "activeworkspace", "activewindow", "layers", "version", "devices", "binds"}


def request(req):
    word = req[2:] if req.startswith("j/") else req
    if word not in READ_ONLY:
        sys.exit(f"hypr.py: {req!r} is not a reading request")
    path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket.sock")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(path)
    s.sendall(req.encode())
    out = b""
    while True:
        d = s.recv(65536)
        if not d:
            break
        out += d
    return out.decode("utf-8", "replace")


if __name__ == "__main__":
    print(request(sys.argv[1] if len(sys.argv) > 1 else "j/version"))
