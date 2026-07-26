"""Diagnose why Windows shows Connected but VPN may not work."""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deploy_vps import BACKEND_ENV, REMOTE_DIR, load_dotenv, run, ssh_connect  # noqa: E402


def main() -> None:
    src = load_dotenv(BACKEND_ENV)
    host = src.get("VPN_AGENT_SSH_HOST") or src.get("VPN_SERVER_HOST")
    print("local_agent_mode=", src.get("VPN_AGENT_MODE"))
    print("local_vpn_host=", src.get("VPN_SERVER_HOST"))
    print("local_vpn_port=", src.get("VPN_SERVER_PORT"))
    pubkey = src.get("VPN_SERVER_PUBLIC_KEY", "")
    print("local_pubkey_ok=", bool(pubkey) and not pubkey.startswith("change"))

    client = ssh_connect(host, src["VPN_AGENT_SSH_PASSWORD"])
    try:
        run(client, "awg show awg0")
        run(client, "ip -4 addr show awg0 || true")
        run(
            client,
            f"grep -E '^(VPN_AGENT_MODE|VPN_SERVER_HOST|VPN_SERVER_PORT|VPN_SERVER_PUBLIC_KEY)=' "
            f"{REMOTE_DIR}/.env",
        )
        run(client, "docker logs bratanvpn-backend --tail 100 2>&1")
        run(
            client,
            "docker exec bratanvpn-backend python -c "
            "\"from app.core.config import settings; "
            "print('mode', settings.vpn_agent_mode); "
            "print('host', settings.vpn_server_host); "
            "print('port', settings.vpn_server_port); "
            "print('pk', settings.vpn_server_public_key[:12]+'...')\"",
        )
    finally:
        client.close()


if __name__ == "__main__":
    main()
