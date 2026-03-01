#!/usr/bin/env python3
# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "aiohttp",
#     "typer",
# ]
# ///
"""
A simple reverse proxy that adds a configurable delay to requests.
Useful for testing slow network conditions or rate limiting behavior.

Run with: uv run scripts/delayed_proxy.py [OPTIONS]
"""

import asyncio
import re
from typing import Annotated

import aiohttp
import aiohttp.web
import typer

SKIP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
}


def make_app(upstream_url: str, delay: float, match: re.Pattern[str] | None) -> aiohttp.web.Application:
    async def handle(request: aiohttp.web.Request) -> aiohttp.web.StreamResponse:
        should_delay = delay > 0 and (match is None or match.search(str(request.rel_url)))
        if should_delay:
            await asyncio.sleep(delay)

        target = upstream_url.rstrip("/") + str(request.rel_url)

        headers = {k: v for k, v in request.headers.items() if k.lower() not in SKIP_HEADERS}
        # Ask upstream not to compress so we can pass bytes through unchanged
        headers["Accept-Encoding"] = "identity"

        async with aiohttp.ClientSession(auto_decompress=False) as session:
            async with session.request(
                method=request.method,
                url=target,
                headers=headers,
                data=request.content,
                allow_redirects=False,
            ) as upstream:
                delayed_tag = f" [delayed {delay}s]" if should_delay else " [no delay]"
                print(f"{request.method} {request.rel_url} -> {upstream.status}{delayed_tag}")
                response = aiohttp.web.StreamResponse(
                    status=upstream.status,
                    headers={k: v for k, v in upstream.headers.items() if k.lower() not in SKIP_HEADERS},
                )
                await response.prepare(request)
                async for chunk in upstream.content.iter_any():
                    await response.write(chunk)
                await response.write_eof()
                return response

    app = aiohttp.web.Application()
    app.router.add_route("*", "/{path_info:.*}", handle)
    return app


def main(
    upstream: Annotated[str, typer.Option("--upstream", "-u", help="Upstream server URL.")] = "http://localhost:8000",
    port: Annotated[int, typer.Option("--port", "-p", help="Port to listen on.")] = 8888,
    delay: Annotated[float, typer.Option("--delay", "-d", help="Delay in seconds before forwarding each request.")] = 2.0,
    match: Annotated[str | None, typer.Option("--match", "-m", help="Regex to match against request path; only matching requests are delayed.")] = None,
) -> None:
    """Reverse proxy that adds a configurable delay to requests."""
    compiled = re.compile(match) if match else None

    print(f"Delayed proxy listening on http://localhost:{port}")
    print(f"Proxying to {upstream} with {delay}s delay", end="")
    print(f" (matching {match!r})" if compiled else "")
    print("Press Ctrl+C to stop\n")

    aiohttp.web.run_app(make_app(upstream, delay, compiled), port=port, print=None)


if __name__ == "__main__":
    typer.run(main)
