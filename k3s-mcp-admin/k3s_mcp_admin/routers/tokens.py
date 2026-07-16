"""Token management router -- view and rotate the MCP auth token.

The token is stored in the config store and also embedded in the
nginx proxy ConfigMap as part of the URL path (``/private_{token}/``).
Rotating the token updates both locations and restarts the proxy.
"""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel

from mcp_admin_core.config import get_config_store

from ..k8s_manager import get_k3s_manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/tokens", tags=["tokens"])


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------


class TokenInfo(BaseModel):
    token_masked: str
    has_token: bool
    history: list[dict[str, Any]] = []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _mask(value: str) -> str:
    """Mask all but the first and last 2 characters of a token."""
    if len(value) <= 4:
        return "****"
    return f"{value[:2]}{'*' * (len(value) - 4)}{value[-2:]}"


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("", response_model=TokenInfo)
async def get_token() -> TokenInfo:
    """Return the current MCP auth token (masked) and rotation history."""
    store = get_config_store()
    cfg = await store.load()
    token = cfg.get("mcp_auth_token", "")
    history = cfg.get("token_history", [])

    return TokenInfo(
        token_masked=_mask(token) if token else "(not set)",
        has_token=bool(token),
        history=history,
    )


@router.post("/rotate")
async def rotate_token() -> dict[str, Any]:
    """Generate a new token, update config and nginx ConfigMap, restart proxy.

    Steps:
    1. Read current token from config store.
    2. Archive current token in ``token_history``.
    3. Generate a new token and save to config store.
    4. Patch the nginx proxy ConfigMap to replace the old URL-path token.
    5. Restart the proxy deployment.
    """
    store = get_config_store()
    cfg = await store.load()

    old_token = cfg.get("mcp_auth_token", "")

    # Archive old token
    history: list[dict[str, Any]] = cfg.get("token_history", [])
    if old_token:
        history.insert(0, {
            "token_masked": _mask(old_token),
            "rotated_at": datetime.now(timezone.utc).isoformat(),
        })
        history = history[:10]  # keep last 10
        cfg["token_history"] = history

    # Generate new token
    new_token = secrets.token_hex(32)
    cfg["mcp_auth_token"] = new_token
    await store.save(cfg)
    logger.info("New MCP auth token generated and saved to config store")

    # Patch nginx ConfigMap and restart proxy
    if old_token:
        try:
            mgr = get_k3s_manager()
            await mgr.rotate_proxy_token(old_token, new_token)
            logger.info("Proxy ConfigMap patched and proxy restarted")
        except Exception as exc:
            logger.error("Failed to update proxy ConfigMap: %s", exc)
            return {
                "status": "partial",
                "token": new_token,
                "message": (
                    "Token rotated in config but failed to update proxy "
                    f"ConfigMap: {exc}. Manually update the proxy."
                ),
            }
    else:
        logger.info("No old token to replace in proxy ConfigMap; skipping patch")

    return {
        "status": "ok",
        "token": new_token,
        "message": "Token rotated successfully. Save it -- shown only once.",
    }
