"""K3s cluster manager -- high-level operations for the K3s MCP Admin GUI.

Wraps :class:`mcp_admin_core.k8s.client.K8sClient` with K3s-specific
constants (deployment names, labels, ConfigMap names) and adds
convenience methods for the Admin dashboard.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, AsyncGenerator

from kubernetes import client as k8s_client
from kubernetes.client.rest import ApiException
from mcp_admin_core.k8s.client import K8sClient

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

NAMESPACE = "mcp-system"
MCP_DEPLOY = "kubernetes-mcp-server"
PROXY_DEPLOY = "mcp-k8s-proxy"
MCP_LABEL = "app.kubernetes.io/name=kubernetes-mcp-server"
PROXY_LABEL = "app.kubernetes.io/name=mcp-k8s-proxy"
PROXY_CONFIG_CM = "mcp-k8s-proxy-config"


# ---------------------------------------------------------------------------
# K3sManager
# ---------------------------------------------------------------------------


class K3sManager:
    """Facade over K8sClient tailored to the K3s MCP deployment.

    All public methods are async; synchronous Kubernetes SDK calls are
    dispatched to a thread via :func:`asyncio.to_thread`.
    """

    def __init__(self) -> None:
        self._k8s = K8sClient(namespace=NAMESPACE)

    # -- Pod status ---------------------------------------------------------

    async def mcp_pod_status(self) -> list[dict[str, Any]]:
        """Return status info for the MCP server pod(s)."""
        return await asyncio.to_thread(self._k8s.get_pod_status, MCP_LABEL)

    async def proxy_pod_status(self) -> list[dict[str, Any]]:
        """Return status info for the proxy pod(s)."""
        return await asyncio.to_thread(self._k8s.get_pod_status, PROXY_LABEL)

    # -- Restart ------------------------------------------------------------

    async def restart_mcp(self) -> None:
        """Trigger a rolling restart of the MCP server deployment."""
        await asyncio.to_thread(self._k8s.restart_deployment, MCP_DEPLOY)

    async def restart_proxy(self) -> None:
        """Trigger a rolling restart of the proxy deployment."""
        await asyncio.to_thread(self._k8s.restart_deployment, PROXY_DEPLOY)

    # -- Logs ---------------------------------------------------------------

    async def stream_mcp_logs(
        self,
        tail: int = 100,
    ) -> AsyncGenerator[tuple[str, str], None]:
        """Stream log lines from the MCP server pod.

        Yields ``(line, pod_name)`` tuples.
        """
        async for item in self._k8s.stream_pod_logs(
            MCP_LABEL,
            tail_lines=tail,
            follow=True,
        ):
            yield item

    # -- Proxy config -------------------------------------------------------

    async def get_proxy_config(self) -> dict[str, str]:
        """Return the data section of the proxy nginx ConfigMap."""
        return await asyncio.to_thread(
            self._k8s.get_configmap, PROXY_CONFIG_CM
        )

    async def rotate_proxy_token(
        self, old_token: str, new_token: str
    ) -> None:
        """Replace the URL-path token inside the nginx ConfigMap and restart.

        Reads the current ``nginx.conf`` value from the proxy ConfigMap,
        replaces all occurrences of ``private_{old_token}`` with
        ``private_{new_token}``, patches the ConfigMap, and restarts the
        proxy deployment so the new config takes effect.
        """
        cm_data = await asyncio.to_thread(
            self._k8s.get_configmap, PROXY_CONFIG_CM
        )
        nginx_conf = cm_data.get("nginx.conf", "")
        if not nginx_conf:
            logger.warning("nginx.conf key not found in ConfigMap %s", PROXY_CONFIG_CM)
            return

        updated_conf = nginx_conf.replace(
            f"private_{old_token}", f"private_{new_token}"
        )

        await asyncio.to_thread(
            self._k8s.patch_configmap,
            PROXY_CONFIG_CM,
            {"nginx.conf": updated_conf},
        )
        logger.info("Patched proxy ConfigMap with new token")

        await self.restart_proxy()
        logger.info("Proxy deployment restarted after token rotation")

    # -- Cluster overview ---------------------------------------------------

    async def cluster_overview(self) -> dict[str, int]:
        """Return high-level cluster counts: nodes, namespaces, pods."""

        def _fetch() -> dict[str, int]:
            core = self._k8s.core
            nodes = core.list_node()
            namespaces = core.list_namespace()
            pods = core.list_pod_for_all_namespaces()
            return {
                "nodes": len(nodes.items),
                "namespaces": len(namespaces.items),
                "pods": len(pods.items),
            }

        return await asyncio.to_thread(_fetch)

    # -- Node operations ----------------------------------------------------

    async def list_nodes(self) -> list[dict[str, Any]]:
        """Return a list of cluster nodes with status details."""

        def _fetch() -> list[dict[str, Any]]:
            core = self._k8s.core
            nodes = core.list_node()
            now = datetime.now(timezone.utc)
            result: list[dict[str, Any]] = []
            for node in nodes.items:
                # Determine status from conditions
                status = "Unknown"
                if node.status and node.status.conditions:
                    for cond in node.status.conditions:
                        if cond.type == "Ready":
                            status = "Ready" if cond.status == "True" else "NotReady"
                            break

                # Determine roles from labels
                roles: list[str] = []
                labels = node.metadata.labels or {}
                for label_key in labels:
                    if label_key.startswith("node-role.kubernetes.io/"):
                        role = label_key.split("/", 1)[1]
                        if role:
                            roles.append(role)
                if not roles:
                    roles = ["<none>"]

                # Age
                age = ""
                if node.metadata.creation_timestamp:
                    ts = node.metadata.creation_timestamp.replace(tzinfo=timezone.utc)
                    delta = now - ts
                    age = _format_age(int(delta.total_seconds()))

                # Resources
                capacity = {}
                allocatable = {}
                if node.status:
                    if node.status.capacity:
                        capacity = dict(node.status.capacity)
                    if node.status.allocatable:
                        allocatable = dict(node.status.allocatable)

                result.append({
                    "name": node.metadata.name,
                    "status": status,
                    "roles": roles,
                    "age": age,
                    "resources": {
                        "capacity": capacity,
                        "allocatable": allocatable,
                    },
                })
            return result

        return await asyncio.to_thread(_fetch)

    # -- Namespace operations -----------------------------------------------

    async def list_namespaces(self) -> list[dict[str, Any]]:
        """Return a list of all namespaces."""

        def _fetch() -> list[dict[str, Any]]:
            core = self._k8s.core
            ns_list = core.list_namespace()
            now = datetime.now(timezone.utc)
            result: list[dict[str, Any]] = []
            for ns in ns_list.items:
                age = ""
                if ns.metadata.creation_timestamp:
                    ts = ns.metadata.creation_timestamp.replace(tzinfo=timezone.utc)
                    delta = now - ts
                    age = _format_age(int(delta.total_seconds()))

                result.append({
                    "name": ns.metadata.name,
                    "status": ns.status.phase if ns.status else "Unknown",
                    "age": age,
                })
            return result

        return await asyncio.to_thread(_fetch)

    # -- Pod operations -----------------------------------------------------

    async def list_pods(self, namespace: str = "") -> list[dict[str, Any]]:
        """Return a list of pods, optionally filtered by namespace.

        If *namespace* is empty, pods from all namespaces are returned.
        """

        def _fetch() -> list[dict[str, Any]]:
            core = self._k8s.core
            if namespace:
                pod_list = core.list_namespaced_pod(namespace)
            else:
                pod_list = core.list_pod_for_all_namespaces()

            now = datetime.now(timezone.utc)
            result: list[dict[str, Any]] = []
            for pod in pod_list.items:
                restarts = 0
                ready_count = 0
                total_containers = 0

                if pod.status and pod.status.container_statuses:
                    for cs in pod.status.container_statuses:
                        total_containers += 1
                        restarts += cs.restart_count
                        if cs.ready:
                            ready_count += 1
                elif pod.spec and pod.spec.containers:
                    total_containers = len(pod.spec.containers)

                age = ""
                if pod.metadata.creation_timestamp:
                    ts = pod.metadata.creation_timestamp.replace(tzinfo=timezone.utc)
                    delta = now - ts
                    age = _format_age(int(delta.total_seconds()))

                phase = pod.status.phase if pod.status else "Unknown"

                result.append({
                    "name": pod.metadata.name,
                    "namespace": pod.metadata.namespace,
                    "phase": phase,
                    "ready": f"{ready_count}/{total_containers}",
                    "restart_count": restarts,
                    "age": age,
                    "node": pod.spec.node_name if pod.spec else "",
                })
            return result

        return await asyncio.to_thread(_fetch)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _format_age(seconds: int) -> str:
    """Format an age in seconds into a human-readable string."""
    if seconds < 60:
        return f"{seconds}s"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m"
    hours = minutes // 60
    if hours < 24:
        return f"{hours}h"
    days = hours // 24
    return f"{days}d"


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------

_manager: K3sManager | None = None


def get_k3s_manager() -> K3sManager:
    """Return the global K3sManager singleton."""
    global _manager  # noqa: PLW0603
    if _manager is None:
        _manager = K3sManager()
    return _manager
