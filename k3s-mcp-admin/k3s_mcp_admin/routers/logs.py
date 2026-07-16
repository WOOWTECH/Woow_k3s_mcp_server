"""Log streaming router -- SSE endpoint and in-memory search.

Provides a Server-Sent Events (SSE) endpoint that streams MCP pod
logs in real-time, plus a search endpoint that queries an in-memory
ring buffer of recently received log lines.
"""

from __future__ import annotations

import asyncio
import collections
import json
import logging
from typing import Any

from fastapi import APIRouter, Query, Request
from fastapi.responses import StreamingResponse

from ..k8s_manager import get_k3s_manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/logs", tags=["logs"])

# ---------------------------------------------------------------------------
# In-memory ring buffer for log search
# ---------------------------------------------------------------------------

_MAX_BUFFER_SIZE = 5000
_log_buffer: collections.deque[dict[str, str]] = collections.deque(maxlen=_MAX_BUFFER_SIZE)


def _add_to_buffer(line: str, pod_name: str) -> None:
    """Append a log line to the ring buffer."""
    _log_buffer.append({"line": line, "pod": pod_name})


# ---------------------------------------------------------------------------
# SSE streaming endpoint
# ---------------------------------------------------------------------------


@router.get("/stream")
async def stream_logs(
    request: Request,
    tail: int = Query(100, ge=1, le=5000, description="Number of tail lines"),
) -> StreamingResponse:
    """Stream MCP server pod logs as Server-Sent Events.

    The client receives events in the format::

        data: {"line": "...", "pod": "pod-name"}

    The stream stays open as long as the client is connected or until
    the pod log stream ends.
    """

    async def event_generator():
        mgr = get_k3s_manager()
        try:
            async for line, pod_name in mgr.stream_mcp_logs(tail=tail):
                # Check if client disconnected
                if await request.is_disconnected():
                    break

                # Add to ring buffer for search
                _add_to_buffer(line, pod_name)

                payload = json.dumps({"line": line, "pod": pod_name})
                yield f"data: {payload}\n\n"
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.error("Log stream error: %s", exc)
            error_payload = json.dumps({"line": f"[error] {exc}", "pod": "system"})
            yield f"data: {error_payload}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# ---------------------------------------------------------------------------
# Log search endpoint
# ---------------------------------------------------------------------------


@router.get("/search")
async def search_logs(
    q: str = Query("", description="Search query (case-insensitive substring match)"),
    limit: int = Query(200, ge=1, le=5000, description="Maximum results to return"),
) -> dict[str, Any]:
    """Search the in-memory log ring buffer.

    Returns matching lines in reverse chronological order (newest first).
    """
    if not q:
        # Return recent lines
        results = list(reversed(_log_buffer))[:limit]
        return {
            "query": q,
            "total_buffered": len(_log_buffer),
            "results": results,
            "count": len(results),
        }

    query_lower = q.lower()
    matches: list[dict[str, str]] = []
    for entry in reversed(_log_buffer):
        if query_lower in entry["line"].lower():
            matches.append(entry)
            if len(matches) >= limit:
                break

    return {
        "query": q,
        "total_buffered": len(_log_buffer),
        "results": matches,
        "count": len(matches),
    }
