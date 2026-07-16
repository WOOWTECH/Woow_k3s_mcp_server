"""K3s MCP tool registry -- defines all 23 tools exposed by the K3s MCP server.

Each tool has a name, human-readable description, category, and a flag
indicating whether it performs a potentially destructive operation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal


@dataclass(frozen=True)
class McpTool:
    """Metadata for a single MCP tool."""

    name: str
    description: str
    category: Literal["core", "config", "helm"]
    dangerous: bool = False


# ---------------------------------------------------------------------------
# Core tools (13) -- pod/node/namespace/event operations
# ---------------------------------------------------------------------------

_CORE_TOOLS: list[McpTool] = [
    McpTool(
        name="pods_list",
        description="List pods across all namespaces",
        category="core",
    ),
    McpTool(
        name="pods_list_in_namespace",
        description="List pods in a specific namespace",
        category="core",
    ),
    McpTool(
        name="pods_get",
        description="Get detailed information about a specific pod",
        category="core",
    ),
    McpTool(
        name="pods_log",
        description="Retrieve logs from a pod",
        category="core",
    ),
    McpTool(
        name="pods_exec",
        description="Execute a command inside a running pod",
        category="core",
        dangerous=True,
    ),
    McpTool(
        name="pods_top",
        description="Show resource usage (CPU/memory) for pods",
        category="core",
    ),
    McpTool(
        name="pods_run",
        description="Run a new pod with a specified image",
        category="core",
        dangerous=True,
    ),
    McpTool(
        name="pods_delete",
        description="Delete a pod",
        category="core",
        dangerous=True,
    ),
    McpTool(
        name="namespaces_list",
        description="List all namespaces in the cluster",
        category="core",
    ),
    McpTool(
        name="events_list",
        description="List cluster events",
        category="core",
    ),
    McpTool(
        name="nodes_log",
        description="Retrieve logs from a node",
        category="core",
    ),
    McpTool(
        name="nodes_top",
        description="Show resource usage for nodes",
        category="core",
    ),
    McpTool(
        name="nodes_stats_summary",
        description="Get node stats summary (CPU, memory, disk, network)",
        category="core",
    ),
]

# ---------------------------------------------------------------------------
# Config tools (6) -- K8s resource CRUD + cluster config
# ---------------------------------------------------------------------------

_CONFIG_TOOLS: list[McpTool] = [
    McpTool(
        name="resources_list",
        description="List Kubernetes resources of a given kind",
        category="config",
    ),
    McpTool(
        name="resources_get",
        description="Get a specific Kubernetes resource by name",
        category="config",
    ),
    McpTool(
        name="resources_create_or_update",
        description="Create or update a Kubernetes resource from YAML/JSON",
        category="config",
        dangerous=True,
    ),
    McpTool(
        name="resources_delete",
        description="Delete a Kubernetes resource",
        category="config",
        dangerous=True,
    ),
    McpTool(
        name="resources_scale",
        description="Scale a deployment or statefulset replica count",
        category="config",
        dangerous=True,
    ),
    McpTool(
        name="configuration_view",
        description="View the MCP server configuration",
        category="config",
    ),
]

# ---------------------------------------------------------------------------
# Helm tools (4) -- Helm chart management
# ---------------------------------------------------------------------------

_HELM_TOOLS: list[McpTool] = [
    McpTool(
        name="helm_list",
        description="List Helm releases in the cluster",
        category="helm",
    ),
    McpTool(
        name="helm_install",
        description="Install or upgrade a Helm chart",
        category="helm",
        dangerous=True,
    ),
    McpTool(
        name="helm_uninstall",
        description="Uninstall a Helm release",
        category="helm",
        dangerous=True,
    ),
    McpTool(
        name="projects_list",
        description="List available Helm chart projects/repositories",
        category="helm",
    ),
]

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

ALL_TOOLS: list[McpTool] = _CORE_TOOLS + _CONFIG_TOOLS + _HELM_TOOLS
"""All 23 K3s MCP tools."""

TOOLS_BY_NAME: dict[str, McpTool] = {t.name: t for t in ALL_TOOLS}
"""Lookup table: tool name -> McpTool."""

TOOLS_BY_CATEGORY: dict[str, list[McpTool]] = {
    "core": _CORE_TOOLS,
    "config": _CONFIG_TOOLS,
    "helm": _HELM_TOOLS,
}
"""Tools grouped by category."""

DANGEROUS_TOOLS: set[str] = {t.name for t in ALL_TOOLS if t.dangerous}
"""Set of tool names that perform destructive operations."""
