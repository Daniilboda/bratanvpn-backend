"""Query recent access_keys from VPS postgres."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deploy_vps import BACKEND_ENV, load_dotenv, run, ssh_connect  # noqa: E402


def main() -> None:
    src = load_dotenv(BACKEND_ENV)
    host = src.get("VPN_AGENT_SSH_HOST") or src.get("VPN_SERVER_HOST")
    client = ssh_connect(host, src["VPN_AGENT_SSH_PASSWORD"])
    try:
        run(
            client,
            "docker exec bratanvpn-postgres psql -U bratanvpn -d bratanvpn -c "
            "\"SELECT status, vpn_ip, left(vpn_public_key,24) AS pk "
            "FROM access_keys ORDER BY id DESC LIMIT 8;\"",
        )
    finally:
        client.close()


if __name__ == "__main__":
    main()
