#!/usr/bin/env python3
"""
OpenClaw PaaS - Cloudflare Tunnel Auto-Initialization Script
Fetches Account ID via zones, finds/creates tunnel, retrieves token,
and saves config for downstream K8s manifest generation.
"""

import json
import os
import sys
import base64
import requests

CF_API_TOKEN = os.environ.get("CF_API_TOKEN", "")
TUNNEL_NAME = os.environ.get("TUNNEL_NAME", "openclaw")
DOMAIN = os.environ.get("OPENCLAW_DOMAIN", "your-domain.example.com")
BASE_URL = "https://api.cloudflare.com/client/v4"

HEADERS = {
    "Authorization": f"Bearer {CF_API_TOKEN}",
    "Content-Type": "application/json",
}


def api_get(path):
    resp = requests.get(f"{BASE_URL}{path}", headers=HEADERS)
    resp.raise_for_status()
    return resp.json()


def api_post(path, payload):
    resp = requests.post(f"{BASE_URL}{path}", headers=HEADERS, json=payload)
    resp.raise_for_status()
    return resp.json()


def main():
    print("=" * 60)
    print("  OpenClaw PaaS - Cloudflare Tunnel Initialization")
    print("=" * 60)

    # Step 1: Get Account ID via zones (token may lack account:read)
    print("\n[1/4] Fetching Cloudflare Account ID via zones...")
    zones_data = api_get("/zones")
    zones = zones_data.get("result", [])
    if not zones:
        print("[ERROR] No zones found. Token may lack zone:read permission.")
        sys.exit(1)
    account_id = zones[0]["account"]["id"]
    account_name = zones[0]["account"]["name"]
    print(f"  -> Account: {account_name}")
    print(f"  -> Account ID: {account_id}")

    # Step 2: Find or create tunnel
    print(f"\n[2/4] Looking for tunnel '{TUNNEL_NAME}'...")
    tunnels_data = api_get(f"/accounts/{account_id}/cfd_tunnel?name={TUNNEL_NAME}&is_deleted=false")
    tunnels = tunnels_data.get("result", [])

    if tunnels:
        tunnel = tunnels[0]
        tunnel_id = tunnel["id"]
        print(f"  -> Found existing tunnel: {tunnel_id}")
    else:
        print(f"  -> Creating tunnel '{TUNNEL_NAME}'...")
        import secrets as sec
        tunnel_secret = base64.b64encode(sec.token_bytes(32)).decode()
        create_data = api_post(f"/accounts/{account_id}/cfd_tunnel", {
            "name": TUNNEL_NAME,
            "tunnel_secret": tunnel_secret,
        })
        tunnel_id = create_data["result"]["id"]
        print(f"  -> Created tunnel: {tunnel_id}")

    # Step 3: Get tunnel token
    print("\n[3/4] Fetching tunnel token...")
    token_data = api_get(f"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/token")
    if token_data.get("success"):
        tunnel_token = token_data["result"]
        print(f"  -> Token obtained (length: {len(tunnel_token)})")
    else:
        print("[ERROR] Failed to retrieve tunnel token.")
        sys.exit(1)

    # Step 4: Save config
    config = {
        "CF_ACCOUNT_ID": account_id,
        "CF_TUNNEL_ID": tunnel_id,
        "CF_TUNNEL_TOKEN": tunnel_token,
        "CF_API_TOKEN": CF_API_TOKEN,
        "DOMAIN": DOMAIN,
        "TUNNEL_NAME": TUNNEL_NAME,
    }
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cf-config.json")
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)

    print(f"\n[4/4] Config saved to: {config_path}")
    print(f"  CF_ACCOUNT_ID  = {account_id}")
    print(f"  CF_TUNNEL_ID   = {tunnel_id}")
    print(f"  CF_TUNNEL_TOKEN = {tunnel_token[:30]}...")
    print("=" * 60)
    return config


if __name__ == "__main__":
    main()
