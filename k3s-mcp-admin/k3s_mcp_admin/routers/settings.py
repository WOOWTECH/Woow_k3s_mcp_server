"""K3s-specific settings router -- MCP server status and restart via K8s API.

Unlike the core settings router (which manages the MCP process via
:class:`McpProcessManager`), this router interacts with the Kubernetes
API to check and restart the MCP server *deployment*.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..k8s_manager import get_k3s_manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/settings", tags=["settings-k3s"])


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------


class McpPodStatus(BaseModel):
    """MCP server pod status from the Kubernetes API."""

    running: bool = False
    pod_name: str = ""
    phase: str = "Unknown"
    ready: bool = False
    restart_count: int = 0
    age: str = ""
    container_statuses: list[dict[str, Any]] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/mcp/status", response_model=McpPodStatus)
async def mcp_status() -> McpPodStatus:
    """Return MCP server pod status from the Kubernetes API.

    This overrides the core settings router's ``/api/settings/mcp/status``
    endpoint to use the K8s API instead of the process manager.
    """
    mgr = get_k3s_manager()
    try:
        pods = await mgr.mcp_pod_status()
        if not pods:
            return McpPodStatus()

        pod = pods[0]
        return McpPodStatus(
            running=pod.get("phase") == "Running" and pod.get("ready", False),
            pod_name=pod.get("name", ""),
            phase=pod.get("phase", "Unknown"),
            ready=pod.get("ready", False),
            restart_count=pod.get("restart_count", 0),
            age=pod.get("age", ""),
            container_statuses=pod.get("container_statuses", []),
        )
    except Exception as exc:
        logger.error("Failed to get MCP pod status: %s", exc)
        return McpPodStatus()


@router.post("/mcp/restart")
async def mcp_restart() -> dict[str, str]:
    """Restart the MCP server deployment via the Kubernetes API.

    Triggers a rolling restart by patching the ``restartedAt``
    annotation on the deployment's pod template.
    """
    mgr = get_k3s_manager()
    try:
        await mgr.restart_mcp()
        return {"status": "ok", "message": "MCP server deployment restarted"}
    except Exception as exc:
        logger.error("Failed to restart MCP deployment: %s", exc)
        return {"status": "error", "message": f"Failed to restart: {exc}"}
