"""Sidecar entry point.

Startup sequence:
  1. Bind a TCP socket to 127.0.0.1:0 so the OS picks a free port.
  2. Generate a random bearer token.
  3. Print ``{"port": N, "token": "..."}`` as the FIRST line of stdout, flushed.
     The Swift app reads exactly this line to learn how to reach us.
  4. Start a watchdog thread that exits the process if the parent (the app) dies.
  5. Hand the bound socket to uvicorn and serve the FastAPI app.

Every request must carry ``Authorization: Bearer <token>`` (enforced by
``token_middleware``). The socket is loopback-only, so combined with the token
no other local user can drive the API.
"""

import asyncio
import json
import os
import secrets
import socket
import sys
import threading
import time

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from . import __version__
from .tags import router as tags_router
from .decode import router as decode_router
from .scp import router as scp_router
from .network import router as network_router
from .anonymize import router as anonymize_router

# Token is generated in ``main()`` and read by the middleware.
_TOKEN: str = ""

app = FastAPI(title="DICOMBench sidecar", version=__version__)
app.include_router(tags_router)
app.include_router(decode_router)
app.include_router(scp_router)
app.include_router(network_router)
app.include_router(anonymize_router)


@app.middleware("http")
async def token_middleware(request: Request, call_next):
    """Reject any request without the correct bearer token."""
    auth = request.headers.get("authorization", "")
    expected = f"Bearer {_TOKEN}"
    # Constant-time compare to avoid leaking the token via timing.
    if not _TOKEN or not secrets.compare_digest(auth, expected):
        return JSONResponse({"detail": "unauthorized"}, status_code=401)
    return await call_next(request)


@app.get("/health")
async def health():
    """Readiness probe used by the app after the handshake."""
    return {"status": "ok", "version": __version__}


@app.get("/version")
async def version():
    return {"version": __version__}


def _parent_watchdog(parent_pid: int) -> None:
    """Exit if the launching app process goes away.

    When the parent dies, ``os.getppid()`` becomes 1 (reparented to launchd).
    We also re-check the recorded PID in case of fast PID reuse.
    """
    while True:
        time.sleep(1.0)
        if os.getppid() != parent_pid:
            os._exit(0)


def main() -> None:
    global _TOKEN

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(128)
    port = sock.getsockname()[1]

    _TOKEN = secrets.token_urlsafe(32)

    # Handshake line — must be the first thing on stdout.
    sys.stdout.write(json.dumps({"port": port, "token": _TOKEN}) + "\n")
    sys.stdout.flush()

    parent_pid = os.getppid()
    if parent_pid > 1:
        threading.Thread(
            target=_parent_watchdog, args=(parent_pid,), daemon=True
        ).start()

    config = uvicorn.Config(app, log_level="warning", access_log=False)
    server = uvicorn.Server(config)
    asyncio.run(server.serve(sockets=[sock]))


if __name__ == "__main__":
    main()
