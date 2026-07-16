"""K3s MCP Admin GUI -- FastAPI application entry point.

Creates the app using the ``mcp-admin-core`` factory and registers
all K3s-specific routers.

Run with::

    uvicorn k3s_mcp_admin.main:app --host 0.0.0.0 --port 8080
"""

from mcp_admin_core.app import create_app

from .routers import cluster, health, logs, settings, tokens, tools

app = create_app(
    title="K3s MCP Admin",
    extra_routers=[
        health.router,
        tools.router,
        tokens.router,
        logs.router,
        cluster.router,
        settings.router,
    ],
)
