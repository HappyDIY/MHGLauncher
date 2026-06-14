from __future__ import annotations

import asyncio
import json
import os
import socket

import uvicorn

from mhglauncher.app import create_app
from mhglauncher.config import Settings


async def serve() -> None:
    settings = Settings()
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(128)
    sock.setblocking(False)
    port = sock.getsockname()[1]
    settings.base_port = port
    print(json.dumps({"event": "ready", "port": port}), flush=True)
    server = uvicorn.Server(
        uvicorn.Config(
            create_app(settings),
            host="127.0.0.1",
            port=port,
            log_level="warning",
        )
    )
    monitor = asyncio.create_task(monitor_parent(server))
    try:
        await server.serve(sockets=[sock])
    finally:
        monitor.cancel()


async def monitor_parent(server: uvicorn.Server) -> None:
    raw_parent = os.environ.get("MHG_PARENT_PID")
    if not raw_parent:
        return
    expected = int(raw_parent)
    while not server.should_exit:
        await asyncio.sleep(1)
        if os.getppid() != expected:
            server.should_exit = True


def main() -> None:
    asyncio.run(serve())


if __name__ == "__main__":
    main()
