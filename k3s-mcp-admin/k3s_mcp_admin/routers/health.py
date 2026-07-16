"""Health check router for the K3s MCP Admin GUI.

Reports the health of the MCP server pod, the nginx proxy pod,
the Cloudflare tunnel, and basic cluster statistics.
"""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx
from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..k8s_manager import NAMESPACE, get_k3s_manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["health"])

MCP_EXTERNAL_URL = os.environ.get(
    "MCP_EXTERNAL_URL", "https://k8s-mcp.woowtech.io"
)

VERSION = "1.0.0"


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------


class ComponentHealth(BaseModel):
    healthy: bool
    pod_name: str = ""
    restart_count: int = 0
    age: str = ""


class TunnelHealth(BaseModel):
    healthy: bool
    url: str = ""


class ClusterInfo(BaseModel):
    nodes: int = 0
    pods: int = 0
    namespaces: int = 0


class HealthResponse(BaseModel):
    app_type: str = "k3s"
    overall_status: str = "ok"
    mcp_server: ComponentHealth = Field(default_factory=ComponentHealth)
    proxy: ComponentHealth = Field(default_factory=ComponentHealth)
    tunnel: TunnelHealth = Field(default_factory=TunnelHealth)
    cluster: ClusterInfo = Field(default_factory=ClusterInfo)
    version: str = VERSION
    namespace: str = NAMESPACE


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Aggregate health of all K3s MCP components."""
    mgr = get_k3s_manager()
    degraded = False
    error = False

    # -- MCP server pod -----------------------------------------------------
    mcp_health = ComponentHealth(healthy=False)
    try:
        mcp_pods = await mgr.mcp_pod_status()
        if mcp_pods:
            pod = mcp_pods[0]
            mcp_health = ComponentHealth(
                healthy=pod.get("ready", False),
                pod_name=pod.get("name", ""),
                restart_count=pod.get("restart_count", 0),
                age=pod.get("age", ""),
            )
            if not mcp_health.healthy:
                degraded = True
        else:
            error = True
    except Exception as exc:
        logger.warning("Failed to check MCP pod health: %s", exc)
        error = True

    # -- Proxy pod ----------------------------------------------------------
    proxy_health = ComponentHealth(healthy=False)
    try:
        proxy_pods = await mgr.proxy_pod_status()
        if proxy_pods:
            pod = proxy_pods[0]
            proxy_health = ComponentHealth(
                healthy=pod.get("ready", False),
                pod_name=pod.get("name", ""),
                restart_count=pod.get("restart_count", 0),
                age=pod.get("age", ""),
            )
            if not proxy_health.healthy:
                degraded = True
        else:
            degraded = True
    except Exception as exc:
        logger.warning("Failed to check proxy pod health: %s", exc)
        degraded = True

    # -- Tunnel (Cloudflare) ------------------------------------------------
    tunnel_health = TunnelHealth(healthy=False, url=MCP_EXTERNAL_URL)
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{MCP_EXTERNAL_URL}/health")
            tunnel_health.healthy = resp.status_code < 500
    except Exception as exc:
        logger.debug("Tunnel health check failed: %s", exc)
        degraded = True

    # -- Cluster stats ------------------------------------------------------
    cluster_info = ClusterInfo()
    try:
        overview = await mgr.cluster_overview()
        cluster_info = ClusterInfo(
            nodes=overview.get("nodes", 0),
            pods=overview.get("pods", 0),
            namespaces=overview.get("namespaces", 0),
        )
    except Exception as exc:
        logger.warning("Failed to get cluster overview: %s", exc)
        degraded = True

    # -- Overall status -----------------------------------------------------
    if error:
        overall = "error"
    elif degraded:
        overall = "degraded"
    else:
        overall = "ok"

    return HealthResponse(
        overall_status=overall,
        mcp_server=mcp_health,
        proxy=proxy_health,
        tunnel=tunnel_health,
        cluster=cluster_info,
    )
