#!/usr/bin/env python3
"""What state are these paths in? Prints one JSON list, one object per path argument, in the order given:

  filecheck.py PATH...

  path           the path as given (~ expanded)
  exists         the path exists
  isdir          it is a folder
  readable       it can be read
  writable       it can be written (for a path that does not exist: a file could be created there, see `creatable`)
  parentExists   its folder exists
  creatable      the file does not exist but its folder exists and can be written, so a write creates it
  dirCreatable   the folder does not exist but the nearest folder above it that does can be written, so `mkdir -p` works

Used by services/FileChecks.qml (Sleepysettings greys out what a missing or read-only file would break). Python standard library
only. It reads metadata and writes nothing.
"""
import json
import os
import sys


def check(p):
    p = os.path.expanduser(p)
    exists = os.path.exists(p)
    parent = os.path.dirname(p) or "."
    parent_exists = os.path.isdir(parent)
    up = parent
    while up and not os.path.isdir(up) and os.path.dirname(up) != up:
        up = os.path.dirname(up)
    return {
        "path": p,
        "exists": exists,
        "isdir": os.path.isdir(p),
        "readable": exists and os.access(p, os.R_OK),
        "writable": exists and os.access(p, os.W_OK),
        "parentExists": parent_exists,
        "creatable": (not exists) and parent_exists and os.access(parent, os.W_OK | os.X_OK),
        "dirCreatable": (not parent_exists) and os.path.isdir(up) and os.access(up, os.W_OK | os.X_OK),
    }


if __name__ == "__main__":
    json.dump([check(a) for a in sys.argv[1:]], sys.stdout)
    sys.stdout.write("\n")
