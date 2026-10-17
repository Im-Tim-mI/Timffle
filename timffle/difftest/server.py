#!/usr/bin/env python3
"""Differential-test harness server.

HTTP  127.0.0.1:18765  serves test SWFs, test data, and collects reports.
TCP   127.0.0.1:18766  socket test server; answers Flash socket policy requests.
Nothing listens on 18767 (used to test refused connections).
"""
import http.server
import os
import socket
import socketserver
import threading
import time
import urllib.parse

ROOT = os.path.dirname(os.path.abspath(__file__))
HTTP_PORT = 18765
SOCK_PORT = 18766
POLICY = (b'<?xml version="1.0"?><cross-domain-policy>'
          b'<allow-access-from domain="*" to-ports="*"/></cross-domain-policy>\x00')


def log(name, msg):
    os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
    with open(os.path.join(ROOT, "logs", name), "a") as f:
        f.write("%s %s\n" % (time.strftime("%H:%M:%S"), msg))


def pattern(n, mul, add):
    return bytes((i * mul + add) & 255 for i in range(n))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):
        log("http.log", "%s %s" % (self.headers.get("User-Agent", "-")[:40], fmt % args))

    def send_body(self, body, ctype="application/octet-stream", code=200):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_delayed(self, body, ctype, delay):
        """Send the headers at once and the body only after `delay` seconds (capped at 5)."""
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.flush()
        time.sleep(min(delay, 5.0))
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        p = u.path
        if p == "/crossdomain.xml":
            return self.send_body(b'<?xml version="1.0"?><cross-domain-policy>'
                                  b'<allow-access-from domain="*"/></cross-domain-policy>', "text/xml")
        if p.startswith("/t/"):  # /t/<runner>/<file>
            path = os.path.join(ROOT, "bin", os.path.basename(p))
            if os.path.isfile(path):
                with open(path, "rb") as f:
                    return self.send_body(f.read(), "application/x-shockwave-flash")
            return self.send_body(b"not found", "text/plain", 404)
        if p == "/data/slow":  # body sent in n chunks with a delay between them
            n = int(q.get("n", ["4"])[0])
            size = int(q.get("size", ["8192"])[0])
            delay = float(q.get("delay", ["0.4"])[0])
            nolen = q.get("nolen", ["0"])[0] == "1"  # omit Content-Length
            cut = int(q.get("cut", ["0"])[0])  # announce n+cut chunks, send n
            body = pattern(n * size, 7, 3)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            if not nolen:
                self.send_header("Content-Length", str(len(body) + cut * size))
            self.end_headers()
            for i in range(n):
                self.wfile.write(body[i * size:(i + 1) * size])
                self.wfile.flush()
                time.sleep(delay)
            return
        if p.startswith("/asset/"):  # /asset/<file>?delay=<s>: file from bin/, headers first, body after the delay
            path = os.path.join(ROOT, "bin", os.path.basename(p))
            if not os.path.isfile(path):
                return self.send_body(b"not found", "text/plain", 404)
            with open(path, "rb") as f:
                body = f.read()
            return self.send_delayed(body, "application/x-shockwave-flash", float(q.get("delay", ["0"])[0]))
        if p == "/data/text":  # /data/text?v=<text>&delay=<s>: the text itself, after the delay
            return self.send_delayed(q.get("v", [""])[0].encode(), "text/plain", float(q.get("delay", ["0"])[0]))
        if p == "/data/blob":
            return self.send_body(pattern(int(q.get("size", ["1000"])[0]), 13, 5))
        if p == "/data/404":
            return self.send_body(b"missing", "text/plain", 404)
        return self.send_body(b"not found", "text/plain", 404)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if u.path == "/report":
            runner = os.path.basename(q.get("runner", ["unknown"])[0])
            test = os.path.basename(q.get("test", ["unknown"])[0])
            d = os.path.join(ROOT, "results", runner)
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, test + ".txt"), "wb") as f:
                f.write(body)
            log("http.log", "REPORT %s/%s %d bytes" % (runner, test, len(body)))
            return self.send_body(b"ok", "text/plain")
        return self.send_body(b"not found", "text/plain", 404)


class ThreadingHTTP(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def sock_client(conn, addr):
    """Protocol: packet = uint32 BE payload length + payload; payload[0] is the command.
    1 ECHO  -> echo the whole packet back, split into two sends 150 ms apart
    2 BIG   -> send 8 x 8192 bytes, 100 ms apart
    3 CLOSE -> server closes the connection
    """
    try:
        conn.settimeout(20)
        first = conn.recv(23, socket.MSG_PEEK)
        if first.startswith(b"<policy-file-request/>"):
            conn.recv(4096)
            conn.sendall(POLICY)
            log("sock.log", "policy request from %s:%d -> policy sent" % addr)
            return
        log("sock.log", "data connection from %s:%d" % addr)
        while True:
            hdr = recv_exact(conn, 4)
            if hdr is None:
                log("sock.log", "client closed")
                return
            n = int.from_bytes(hdr, "big")
            payload = recv_exact(conn, n)
            if payload is None:
                return
            cmd = payload[0]
            log("sock.log", "packet len=%d cmd=%d" % (n, cmd))
            if cmd == 1:
                pkt = hdr + payload
                half = len(pkt) // 2
                conn.sendall(pkt[:half])
                time.sleep(0.15)
                conn.sendall(pkt[half:])
            elif cmd == 2:
                data = pattern(8 * 8192, 3, 1)
                for i in range(8):
                    conn.sendall(data[i * 8192:(i + 1) * 8192])
                    time.sleep(0.1)
            elif cmd == 3:
                time.sleep(0.1)
                conn.shutdown(socket.SHUT_RDWR)
                log("sock.log", "server closed connection")
                return
    except Exception as e:  # noqa: BLE001 - log and drop the connection
        log("sock.log", "error %r" % (e,))
    finally:
        conn.close()


def sock_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", SOCK_PORT))
    s.listen(16)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=sock_client, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    threading.Thread(target=sock_server, daemon=True).start()
    ThreadingHTTP(("127.0.0.1", HTTP_PORT), Handler).serve_forever()
