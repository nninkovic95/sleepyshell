"""A request counter for the image tests: a tiny server on 127.0.0.1 that logs every connection it gets.

hits_server.py LOG PORTFILE
Listens on a port the system picks and writes it to PORTFILE. Every connection adds one line to LOG: the
path of an HTTP request, or "?" for anything else (an https:// fetch sends a TLS hello, which still
counts). Answers 404. Runs until killed. Python standard library only.
"""
import os
import socketserver
import sys

LOG, PORTFILE = sys.argv[1], sys.argv[2]


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        path = "?"
        try:
            data = self.request.recv(2048)
            parts = data.split(b"\r\n", 1)[0].split()
            if len(parts) >= 2 and parts[0].isalpha():
                path = parts[1].decode("latin-1")
        except OSError:
            pass
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(path + "\n")
        try:
            self.request.sendall(b"HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n")
        except OSError:
            pass


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


with Server(("127.0.0.1", 0), Handler) as srv:
    with open(PORTFILE + ".tmp", "w", encoding="utf-8") as f:
        f.write(str(srv.server_address[1]))
    os.replace(PORTFILE + ".tmp", PORTFILE)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
