"""Sync VPN_* settings from backend/.env to root .env and VPS compose .env."""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deploy_vps import BACKEND_ENV, REMOTE_DIR, load_dotenv, run, ssh_connect  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

KEYS = [
    "VPN_SERVER_NAME",
    "VPN_SERVER_HOST",
    "VPN_SERVER_PORT",
    "VPN_SERVER_PUBLIC_KEY",
    "VPN_JC",
    "VPN_JMIN",
    "VPN_JMAX",
    "VPN_S1",
    "VPN_S2",
    "VPN_S3",
    "VPN_S4",
    "VPN_H1",
    "VPN_H2",
    "VPN_H3",
    "VPN_H4",
    "VPN_I1",
]


def upsert_env(path: Path, updates: dict[str, str]) -> None:
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    for key, value in updates.items():
        line = f"{key}={value}"
        pattern = rf"^{re.escape(key)}=.*$"
        if re.search(pattern, text, flags=re.M):
            text = re.sub(pattern, line, text, count=1, flags=re.M)
        else:
            text = text.rstrip() + "\n" + line + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    src = load_dotenv(BACKEND_ENV)
    updates = {key: src.get(key, "") for key in KEYS}

    root_env = ROOT / ".env"
    upsert_env(root_env, updates)
    print("updated", root_env)
    print("VPN_SERVER_PUBLIC_KEY=", updates["VPN_SERVER_PUBLIC_KEY"])
    print("VPN_SERVER_HOST=", updates["VPN_SERVER_HOST"])
    print("VPN_SERVER_PORT=", updates["VPN_SERVER_PORT"])

    host = src.get("VPN_AGENT_SSH_HOST") or src.get("VPN_SERVER_HOST")
    client = ssh_connect(host, src["VPN_AGENT_SSH_PASSWORD"])
    try:
        sftp = client.open_sftp()
        with sftp.file("/tmp/vpn_env_updates.json", "w") as handle:
            handle.write(json.dumps(updates))
        sftp.close()

        run(
            client,
            "python3 - <<'PY'\n"
            "import json, re\n"
            "from pathlib import Path\n"
            "updates = json.loads(Path('/tmp/vpn_env_updates.json').read_text())\n"
            f"path = Path('{REMOTE_DIR}/.env')\n"
            "text = path.read_text()\n"
            "for key, value in updates.items():\n"
            "    line = f'{key}={value}'\n"
            "    pattern = rf'^{re.escape(key)}=.*$'\n"
            "    if re.search(pattern, text, flags=re.M):\n"
            "        text = re.sub(pattern, line, text, count=1, flags=re.M)\n"
            "    else:\n"
            "        text = text.rstrip() + '\\n' + line + '\\n'\n"
            "path.write_text(text)\n"
            "for line in path.read_text().splitlines():\n"
            "    if line.startswith('VPN_SERVER_PUBLIC_KEY='):\n"
            "        print('remote_pubkey_ok', line.split('=',1)[1] == updates['VPN_SERVER_PUBLIC_KEY'])\n"
            "    if line.startswith('VPN_SERVER_HOST='):\n"
            "        print(line)\n"
            "PY",
        )
        run(
            client,
            f"cd {REMOTE_DIR} && docker compose up -d backend --force-recreate",
            timeout=180,
        )
        time.sleep(18)
        run(
            client,
            "docker exec bratanvpn-backend python -c "
            "\"from app.core.config import settings; "
            "print(settings.vpn_server_public_key); "
            "print(settings.vpn_server_host); "
            "print(settings.vpn_server_port)\"",
        )
    finally:
        client.close()


if __name__ == "__main__":
    main()
