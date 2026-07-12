#!/usr/bin/env python3
"""Build a protected sing-box config from a decoded URI subscription."""

from __future__ import annotations

import argparse
import json
import secrets
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit


def one(query: dict[str, list[str]], key: str, default: str = "") -> str:
    values = query.get(key)
    return values[0] if values else default


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--subscription", required=True, type=Path)
    parser.add_argument("--node", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    selected = None
    for raw_line in args.subscription.read_text().splitlines():
        line = raw_line.strip()
        if not line.startswith("vless://"):
            continue
        parsed = urlsplit(line)
        if unquote(parsed.fragment) == args.node:
            selected = parsed
            break
    if selected is None:
        raise SystemExit("requested VLESS node was not found")

    query = parse_qs(selected.query)
    if one(query, "security") != "tls" or one(query, "type") != "ws":
        raise SystemExit("requested node is not VLESS over WebSocket and TLS")
    if not selected.hostname or not selected.port or not selected.username:
        raise SystemExit("requested node has incomplete connection parameters")

    proxy_user = "openchoreo"
    proxy_password = secrets.token_urlsafe(24)
    server_name = one(query, "sni") or one(query, "host") or selected.hostname
    websocket_host = one(query, "host") or server_name

    outbound = {
        "type": "vless",
        "tag": "proxy",
        "server": selected.hostname,
        "server_port": selected.port,
        "uuid": unquote(selected.username),
        "tls": {
            "enabled": True,
            "server_name": server_name,
            "insecure": one(query, "insecure") in {"1", "true"},
            "utls": {
                "enabled": True,
                "fingerprint": one(query, "fp", "chrome"),
            },
        },
        "transport": {
            "type": "ws",
            "path": one(query, "path", "/"),
            "headers": {"Host": websocket_host},
        },
    }

    config = {
        "log": {"level": "info", "timestamp": True},
        "inbounds": [
            {
                "type": "mixed",
                "tag": "lan-proxy",
                "listen": "0.0.0.0",
                "listen_port": 3128,
                "users": [
                    {"username": proxy_user, "password": proxy_password}
                ],
            }
        ],
        "outbounds": [outbound, {"type": "direct", "tag": "direct"}],
        "route": {
            "rules": [
                {
                    "ip_is_private": True,
                    "action": "route",
                    "outbound": "direct",
                }
            ],
            "final": "proxy",
            "auto_detect_interface": True,
        },
    }

    args.output_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    config_path = args.output_dir / "config.json"
    credentials_path = args.output_dir / "proxy.env"
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    credentials_path.write_text(
        "PROXY_URL="
        f"http://{proxy_user}:{proxy_password}@192.168.2.184:3128\n"
    )
    config_path.chmod(0o600)
    credentials_path.chmod(0o600)


if __name__ == "__main__":
    main()
