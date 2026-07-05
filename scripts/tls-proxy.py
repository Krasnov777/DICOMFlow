#!/usr/bin/env python3
"""TLS-terminating proxy for DICOM TLS testing.

Listens with TLS on --listen and forwards plaintext to --target, so the app's
DICOM TLS client can be verified against the (plaintext) Orthanc without
touching the shared PACS. Generates a self-signed cert on first run.

  python3 scripts/tls-proxy.py --listen 4243 --target 127.0.0.1:4242 \
      --cert /tmp/dicom-tls/cert.pem --key /tmp/dicom-tls/key.pem
"""
import argparse, os, socket, ssl, subprocess, threading, sys

def ensure_cert(cert, key):
    if os.path.exists(cert) and os.path.exists(key):
        return
    os.makedirs(os.path.dirname(cert), exist_ok=True)
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key, "-out", cert, "-days", "30",
        "-subj", "/CN=127.0.0.1",
        "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost",
    ], check=True, capture_output=True)
    print(f"generated self-signed cert: {cert}")

def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try: s.shutdown(socket.SHUT_RDWR)
            except OSError: pass

def handle(conn, target):
    try:
        upstream = socket.create_connection(target, timeout=10)
    except OSError as e:
        print(f"upstream connect failed: {e}"); conn.close(); return
    threading.Thread(target=pump, args=(conn, upstream), daemon=True).start()
    pump(upstream, conn)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=int, default=4243)
    ap.add_argument("--target", default="127.0.0.1:4242")
    ap.add_argument("--cert", default="/tmp/dicom-tls/cert.pem")
    ap.add_argument("--key", default="/tmp/dicom-tls/key.pem")
    args = ap.parse_args()

    ensure_cert(args.cert, args.key)
    host, port = args.target.rsplit(":", 1)
    target = (host, int(port))

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(args.cert, args.key)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.listen))
    srv.listen(8)
    print(f"TLS :{args.listen} → {args.target}  (cert {args.cert})", flush=True)

    while True:
        raw, _ = srv.accept()
        try:
            conn = ctx.wrap_socket(raw, server_side=True)
        except ssl.SSLError as e:
            print(f"handshake failed: {e}")   # e.g. plaintext client
            raw.close(); continue
        threading.Thread(target=handle, args=(conn, target), daemon=True).start()

if __name__ == "__main__":
    sys.exit(main())
