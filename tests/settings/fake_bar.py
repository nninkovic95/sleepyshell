"""A stand-in for the bar's end of the settings socket, for tests/settings/linked-apply.sh. It takes the window's
connection and reads its messages; then, by MODE:
  die      on the first commit it closes everything without answering (a bar that crashed before it wrote the file)
  answer2  once two commits have come it answers each with `committed` for its keys (a bar slower than two Applies)

fake_bar.py SOCKET_PATH LOG [MODE]
Every message line it reads goes into LOG; "died" or "answered" is the last line. Python standard library only.
"""
import json
import os
import socket
import sys

PATH, LOG = sys.argv[1], sys.argv[2]
MODE = sys.argv[3] if len(sys.argv) > 3 else "die"

srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(PATH)
srv.listen(1)
conn, _ = srv.accept()
buf = b""
commits = []
with open(LOG, "a", encoding="utf-8") as log:
    while True:
        data = conn.recv(65536)
        if not data:
            log.write("window closed\n")
            break
        buf += data
        lines = buf.split(b"\n")
        buf = lines.pop()
        for line in lines:
            text = line.decode(errors="replace")
            log.write(text + "\n")
            if '"type":"commit"' in text:
                commits.append(list(json.loads(text).get("values", {}).keys()))
        if MODE == "die" and commits:
            break
        if MODE == "answer2" and len(commits) >= 2:
            for keys in commits:
                conn.sendall((json.dumps({"type": "committed", "keys": keys}) + "\n").encode())
            log.write("answered\n")
            log.flush()
            # stay linked until the window is done
            while conn.recv(65536):
                pass
            break
    conn.close()
    srv.close()
    os.unlink(PATH)
    if MODE == "die":
        log.write("died\n")
