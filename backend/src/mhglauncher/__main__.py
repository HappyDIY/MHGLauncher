from __future__ import annotations

import asyncio
import json
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
    print(json.dumps({"event": "ready", "port": port}), flush=True)
    server = uvicorn.Server(
        uvicorn.Config(
            create_app(settings),
            host="127.0.0.1",
            port=port,
            log_level="warning",
        )
    )
    await server.serve(sockets=[sock])


def main() -> None:
    asyncio.run(serve())


if __name__ == "__main__":
    main()

