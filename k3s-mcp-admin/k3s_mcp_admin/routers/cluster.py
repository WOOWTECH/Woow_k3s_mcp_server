"""Cluster information router -- nodes, namespaces, and pods.

Provides read-only endpoints that surface cluster state from the
Kubernetes API via :class:`k3s_mcp_admin.k8s_manager.K3sManager`.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

from ..k8s_manager import get_k3s_manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/cluster", tags=["cluster"])


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------


class ClusterOverview(BaseModel):
    nodes: int = 0
    namespaces: int = 0
    pods: int = 0


class NodeInfo(BaseModel):
    name: str
    status: str
    roles: list[str] = Field(default_factory=list)
    age: str = ""
    resources: dict[str, Any] = Field(default_factory=dict)


class NamespaceInfo(BaseModel):
    name: str
    status: str = "Active"
    age: str = ""


class PodInfo(BaseModel):
    name: str
    namespace: str = ""
    phase: str = "Unknown"
    ready: str = "0/0"
    restart_count: int = 0
    age: str = ""
    node: str = ""


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/overview", response_model=ClusterOverview)
async def cluster_overview() -> ClusterOverview:
    """Return high-level cluster counts."""
    mgr = get_k3s_manager()
    try:
        overview = await mgr.cluster_overview()
        return ClusterOverview(**overview)
    except Exception as exc:
        logger.error("Failed to get cluster overview: %s", exc)
        return ClusterOverview()


@router.get("/nodes", response_model=list[NodeInfo])
async def list_nodes() -> list[NodeInfo]:
    """Return all cluster nodes with status, roles, age, and resources."""
    mgr = get_k3s_manager()
    try:
        nodes = await mgr.list_nodes()
        return [NodeInfo(**n) for n in nodes]
    except Exception as exc:
        logger.error("Failed to list nodes: %s", exc)
        return []


@router.get("/namespaces", response_model=list[NamespaceInfo])
async def list_namespaces() -> list[NamespaceInfo]:
    """Return all namespaces."""
    mgr = get_k3s_manager()
    try:
        namespaces = await mgr.list_namespaces()
        return [NamespaceInfo(**ns) for ns in namespaces]
    except Exception as exc:
        logger.error("Failed to list namespaces: %s", exc)
        return []


@router.get("/pods", response_model=list[PodInfo])
async def list_pods(
    namespace: str = Query("", description="Filter by namespace (empty = all)"),
) -> list[PodInfo]:
    """Return pods, optionally filtered by namespace."""
    mgr = get_k3s_manager()
    try:
        pods = await mgr.list_pods(namespace=namespace)
        return [PodInfo(**p) for p in pods]
    except Exception as exc:
        logger.error("Failed to list pods: %s", exc)
        return []
