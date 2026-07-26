"""Deploy BratanVPN stack to VPS over SSH/SFTP. Secrets stay in local .env files."""

from __future__ import annotations

import io
import os
import posixpath
import sys
import tarfile
import time
from pathlib import Path

import paramiko

ROOT = Path(__file__).resolve().parents[2]
BACKEND_ENV = ROOT / "backend" / ".env"
ROOT_ENV_EXAMPLE = ROOT / ".env.example"
REMOTE_DIR = "/opt/bratanvpn"

INCLUDE_DIRS = [
    "backend/app",
    "backend/alembic",
    "backend/alembic.ini",
    "backend/pyproject.toml",
    "backend/Dockerfile",
    "backend/docker-entrypoint.sh",
    "backend/.dockerignore",
    "server/caddy",
    "server/amneziawg",
    "docker-compose.yml",
    ".env.example",
    "docs/DEPLOYMENT_DOCKER.md",
]

SKIP_NAME_PARTS = {
    "__pycache__",
    ".pyc",
    ".venv",
    ".git",
    "tests",
    ".pytest_cache",
    ".ruff_cache",
}


def load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        raise SystemExit(f"Missing env file: {path}")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    if parts & SKIP_NAME_PARTS:
        return True
    name = path.name
    return any(token in name for token in SKIP_NAME_PARTS)


def add_path_to_tar(tar: tarfile.TarFile, rel: str) -> None:
    full = ROOT / rel
    if not full.exists():
        raise SystemExit(f"Missing path for upload: {rel}")
    if full.is_file():
        tar.add(full, arcname=rel.replace("\\", "/"))
        return
    for file_path in full.rglob("*"):
        if file_path.is_dir() or should_skip(file_path):
            continue
        arc = file_path.relative_to(ROOT).as_posix()
        tar.add(file_path, arcname=arc)


def build_archive() -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        for rel in INCLUDE_DIRS:
            add_path_to_tar(tar, rel)
    return buffer.getvalue()


def build_remote_env(local: dict[str, str]) -> str:
    """Compose .env for VPS. Prefer IP/HTTP first if no domain configured."""
    password = local.get("VPN_AGENT_SSH_PASSWORD", "")
    admin = local.get("ADMIN_API_KEY", "change-me")
    pg_password = local.get("POSTGRES_PASSWORD", "bratanvpn_password")
    # Keep same DB password as local default unless overridden in root .env later.
    if pg_password == "change-me-strong-password":
        pg_password = "bratanvpn_password"

    host = local.get("VPN_SERVER_HOST", "127.0.0.1")
    lines = [
        "SITE_ADDRESS=api.bratanvpn.com",
        "POSTGRES_DB=bratanvpn",
        "POSTGRES_USER=bratanvpn",
        f"POSTGRES_PASSWORD={pg_password}",
        f"APP_NAME={local.get('APP_NAME', 'BratanVPN API')}",
        f"APP_VERSION={local.get('APP_VERSION', '0.1.0')}",
        "DEBUG=false",
        f"ADMIN_API_KEY={admin}",
        f"VPN_SERVER_NAME={local.get('VPN_SERVER_NAME', 'Основной')}",
        f"VPN_SERVER_HOST={host}",
        f"VPN_SERVER_PORT={local.get('VPN_SERVER_PORT', '51820')}",
        f"VPN_SERVER_PUBLIC_KEY={local.get('VPN_SERVER_PUBLIC_KEY', '')}",
        f"VPN_JC={local.get('VPN_JC', '4')}",
        f"VPN_JMIN={local.get('VPN_JMIN', '64')}",
        f"VPN_JMAX={local.get('VPN_JMAX', '1024')}",
        f"VPN_S1={local.get('VPN_S1', '32')}",
        f"VPN_S2={local.get('VPN_S2', '48')}",
        f"VPN_S3={local.get('VPN_S3', '24')}",
        f"VPN_S4={local.get('VPN_S4', '12')}",
        f"VPN_H1={local.get('VPN_H1', '1')}",
        f"VPN_H2={local.get('VPN_H2', '2')}",
        f"VPN_H3={local.get('VPN_H3', '3')}",
        f"VPN_H4={local.get('VPN_H4', '4')}",
        f"VPN_I1={local.get('VPN_I1', '')}",
        "VPN_AGENT_MODE=ssh",
        "VPN_AGENT_PATH=/usr/local/sbin/bratanvpn-awg-agent",
        "VPN_AGENT_SSH_HOST=host.docker.internal",
        "VPN_AGENT_SSH_USER=root",
        f"VPN_AGENT_SSH_PASSWORD={password}",
        "VPN_AGENT_SSH_PORT=22",
        f"TELEGRAM_BOT_TOKEN={local.get('TELEGRAM_BOT_TOKEN', '')}",
        f"TELEGRAM_CHAT_ID={local.get('TELEGRAM_CHAT_ID', '')}",
        f"TELEGRAM_ALERT_COOLDOWN_SECONDS={local.get('TELEGRAM_ALERT_COOLDOWN_SECONDS', '900')}",
        f"HEALTH_DISK_MIN_MB={local.get('HEALTH_DISK_MIN_MB', '500')}",
        "",
    ]
    return "\n".join(lines)


def ssh_connect(host: str, password: str) -> paramiko.SSHClient:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=host,
        port=22,
        username="root",
        password=password,
        timeout=45,
        allow_agent=False,
        look_for_keys=False,
    )
    return client


def _safe_print(text: str) -> None:
    try:
        print(text)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((text + "\n").encode("utf-8", errors="replace"))


def run(client: paramiko.SSHClient, command: str, timeout: int = 600) -> str:
    _safe_print(f"$ {command}")
    _stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    if out.strip():
        _safe_print(out.rstrip())
    if err.strip():
        try:
            print(err.rstrip(), file=sys.stderr)
        except UnicodeEncodeError:
            sys.stderr.buffer.write((err.rstrip() + "\n").encode("utf-8", errors="replace"))
    if exit_code != 0:
        raise SystemExit(f"Remote command failed ({exit_code}): {command}")
    return out


def main() -> None:
    local = load_dotenv(BACKEND_ENV)
    host = local.get("VPN_AGENT_SSH_HOST") or local.get("VPN_SERVER_HOST")
    password = local.get("VPN_AGENT_SSH_PASSWORD")
    if not host or not password:
        raise SystemExit("VPN_AGENT_SSH_HOST/VPN_SERVER_HOST and password required in backend/.env")

    print(f"Connecting to {host} ...")
    client = ssh_connect(host, password)
    try:
        run(client, "uname -a")
        run(
            client,
            "if ! command -v docker >/dev/null 2>&1; then "
            "curl -fsSL https://get.docker.com | sh; "
            "systemctl enable --now docker; "
            "fi; docker --version; docker compose version",
            timeout=900,
        )
        run(client, f"mkdir -p {REMOTE_DIR}")

        # Ensure awg agent is installed on host.
        run(
            client,
            "if [ ! -x /usr/local/sbin/bratanvpn-awg-agent ]; then "
            "echo 'WARN: bratanvpn-awg-agent missing on host'; "
            "fi; "
            "ls -la /usr/local/sbin/bratanvpn-awg-agent || true",
        )

        archive = build_archive()
        print(f"Upload archive ({len(archive)} bytes) ...")
        sftp = client.open_sftp()
        try:
            remote_tar = posixpath.join(REMOTE_DIR, "bratanvpn-deploy.tgz")
            with sftp.file(remote_tar, "wb") as remote_file:
                remote_file.write(archive)
            env_text = build_remote_env(local)
            with sftp.file(posixpath.join(REMOTE_DIR, ".env"), "w") as env_file:
                env_file.write(env_text)
        finally:
            sftp.close()

        run(
            client,
            f"cd {REMOTE_DIR} && tar -xzf bratanvpn-deploy.tgz && rm -f bratanvpn-deploy.tgz && "
            "chmod +x backend/docker-entrypoint.sh server/amneziawg/bratanvpn-awg-agent.sh && "
            "sed -i 's/\\r$//' backend/docker-entrypoint.sh server/amneziawg/bratanvpn-awg-agent.sh && "
            "install -m 750 server/amneziawg/bratanvpn-awg-agent.sh /usr/local/sbin/bratanvpn-awg-agent",
        )

        # Allow container -> host SSH for agent (same machine).
        run(
            client,
            "grep -q '^PermitRootLogin' /etc/ssh/sshd_config && "
            "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true; "
            "grep -q '^PasswordAuthentication' /etc/ssh/sshd_config && "
            "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || "
            "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config; "
            "systemctl reload ssh || systemctl reload sshd || true",
        )

        run(
            client,
            f"cd {REMOTE_DIR} && docker compose down --remove-orphans || true && "
            "docker compose up -d --build",
            timeout=1200,
        )
        time.sleep(8)
        run(client, f"cd {REMOTE_DIR} && docker compose ps")
        run(
            client,
            "curl -fsS http://127.0.0.1/api/v1/health || "
            "curl -fsS http://127.0.0.1:80/api/v1/health || true",
        )
        print("Deploy finished.")
        print(f"Health URL (HTTP): http://{host}/api/v1/health")
    finally:
        client.close()


if __name__ == "__main__":
    main()
