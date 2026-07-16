"""Tools router -- list and enable/disable K3s MCP tools.

Tools are defined in :mod:`k3s_mcp_admin.tool_registry`.  The enabled/
disabled state is persisted in the config store under the ``tools``
section (``tools.disabled`` list).
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from mcp_admin_core.config import get_config_store

from ..tool_registry import ALL_TOOLS

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/tools", tags=["tools"])


# ---------------------------------------------------------------------------
# Response / request models
# ---------------------------------------------------------------------------


class ToolItem(BaseModel):
    name: str
    description: str
    category: str
    dangerous: bool
    enabled: bool


class ToolsResponse(BaseModel):
    tools: list[ToolItem]
    total: int
    enabled_count: int
    disabled_count: int


class ToolsUpdateRequest(BaseModel):
    disabled: list[str] = Field(
        default_factory=list,
        description="List of tool names to disable",
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("", response_model=ToolsResponse)
async def list_tools() -> ToolsResponse:
    """Return all K3s MCP tools with their enabled/disabled status."""
    store = get_config_store()
    tools_cfg = await store.get("tools", {})
    disabled: list[str] = tools_cfg.get("disabled", [])

    items: list[ToolItem] = []
    for tool in ALL_TOOLS:
        items.append(
            ToolItem(
                name=tool.name,
                description=tool.description,
                category=tool.category,
                dangerous=tool.dangerous,
                enabled=tool.name not in disabled,
            )
        )

    enabled_count = sum(1 for t in items if t.enabled)
    disabled_count = len(items) - enabled_count

    return ToolsResponse(
        tools=items,
        total=len(items),
        enabled_count=enabled_count,
        disabled_count=disabled_count,
    )


@router.put("")
async def update_tools(body: ToolsUpdateRequest) -> dict[str, Any]:
    """Update the list of disabled tools in the config store."""
    store = get_config_store()
    tools_cfg = await store.get("tools", {})
    tools_cfg["disabled"] = body.disabled
    await store.put("tools", tools_cfg)

    logger.info("Updated disabled tools: %s", body.disabled)
    return {
        "status": "ok",
        "disabled": body.disabled,
        "message": f"{len(body.disabled)} tool(s) disabled",
    }
