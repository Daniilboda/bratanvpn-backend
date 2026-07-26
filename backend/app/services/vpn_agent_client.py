"""Call AmneziaWG host agent via SSH or local subprocess (no arbitrary shell)."""

from __future__ import annotations

import asyncio
import re
import shlex
import subprocess

import paramiko

from app.core.config import settings

_PUBLIC_KEY_RE = re.compile(r"^[A-Za-z0-9+/]{43}=$")
_VPN_IP_RE = re.compile(
    r"^10\.8\.0\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$"
)


class VpnAgentError(Exception):
    """Ошибка вызова VPN-агента на сервере."""


def _validate_public_key(public_key: str) -> None:
    if not _PUBLIC_KEY_RE.fullmatch(public_key):
        raise VpnAgentError("invalid public key format")


def _validate_vpn_ip(vpn_ip: str) -> None:
    if not _VPN_IP_RE.fullmatch(vpn_ip):
        raise VpnAgentError("invalid vpn_ip format")
    if vpn_ip in {"10.8.0.0", "10.8.0.1", "10.8.0.255"}:
        raise VpnAgentError("vpn_ip is not allowed")


def _build_remote_command(args: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in args)


def _run_agent_ssh(args: list[str]) -> str:
    if not settings.vpn_agent_ssh_password:
        raise VpnAgentError("VPN_AGENT_SSH_PASSWORD is not set")

    command = _build_remote_command([settings.vpn_agent_path, *args])

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            hostname=settings.vpn_agent_ssh_host,
            port=settings.vpn_agent_ssh_port,
            username=settings.vpn_agent_ssh_user,
            password=settings.vpn_agent_ssh_password,
            timeout=30,
            allow_agent=False,
            look_for_keys=False,
        )
        _stdin, stdout, stderr = client.exec_command(command, timeout=60)
        exit_code = stdout.channel.recv_exit_status()
        out = stdout.read().decode("utf-8", errors="replace").strip()
        err = stderr.read().decode("utf-8", errors="replace").strip()
    finally:
        client.close()

    if exit_code != 0:
        details = err or out or f"exit code {exit_code}"
        raise VpnAgentError(details)

    return out


def _run_agent_local(args: list[str]) -> str:
    """Run fixed agent argv on this host (no shell interpolation)."""
    command = [settings.vpn_agent_path, *args]
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
            shell=False,
        )
    except FileNotFoundError as exc:
        raise VpnAgentError(f"agent not found: {settings.vpn_agent_path}") from exc
    except subprocess.TimeoutExpired as exc:
        raise VpnAgentError("agent timed out") from exc

    out = (completed.stdout or "").strip()
    err = (completed.stderr or "").strip()
    if completed.returncode != 0:
        details = err or out or f"exit code {completed.returncode}"
        raise VpnAgentError(details)
    return out


def _run_agent(args: list[str]) -> str:
    mode = settings.vpn_agent_mode.strip().lower()
    if mode == "ssh":
        return _run_agent_ssh(args)
    if mode == "local":
        return _run_agent_local(args)
    raise VpnAgentError(f"unsupported vpn_agent_mode: {settings.vpn_agent_mode}")


def add_peer(public_key: str, vpn_ip: str) -> str:
    _validate_public_key(public_key)
    _validate_vpn_ip(vpn_ip)
    return _run_agent(["add", public_key, vpn_ip])


def remove_peer(public_key: str) -> str:
    _validate_public_key(public_key)
    return _run_agent(["remove", public_key])


def peer_exists(public_key: str) -> bool:
    _validate_public_key(public_key)
    try:
        _run_agent(["exists", public_key])
        return True
    except VpnAgentError:
        return False


def agent_status() -> str:
    return _run_agent(["status"])


async def add_peer_async(public_key: str, vpn_ip: str) -> str:
    return await asyncio.to_thread(add_peer, public_key, vpn_ip)


async def remove_peer_async(public_key: str) -> str:
    return await asyncio.to_thread(remove_peer, public_key)


async def peer_exists_async(public_key: str) -> bool:
    return await asyncio.to_thread(peer_exists, public_key)


async def agent_status_async() -> str:
    return await asyncio.to_thread(agent_status)


def _check_internet_local() -> str:
    command = [
        "curl",
        "-fsS",
        "--max-time",
        "5",
        "-o",
        "/dev/null",
        "https://1.1.1.1",
    ]
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
            shell=False,
        )
    except FileNotFoundError as exc:
        raise VpnAgentError("curl not found") from exc
    except subprocess.TimeoutExpired as exc:
        raise VpnAgentError("internet check timed out") from exc

    if completed.returncode != 0:
        details = (completed.stderr or completed.stdout or "curl failed").strip()
        raise VpnAgentError(details)
    return "ok"


def _check_internet_ssh() -> str:
    if not settings.vpn_agent_ssh_password:
        raise VpnAgentError("VPN_AGENT_SSH_PASSWORD is not set")

    # Fixed command only — not built from user input.
    command = "curl -fsS --max-time 5 -o /dev/null https://1.1.1.1"

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            hostname=settings.vpn_agent_ssh_host,
            port=settings.vpn_agent_ssh_port,
            username=settings.vpn_agent_ssh_user,
            password=settings.vpn_agent_ssh_password,
            timeout=30,
            allow_agent=False,
            look_for_keys=False,
        )
        _stdin, stdout, stderr = client.exec_command(command, timeout=30)
        exit_code = stdout.channel.recv_exit_status()
        out = stdout.read().decode("utf-8", errors="replace").strip()
        err = stderr.read().decode("utf-8", errors="replace").strip()
    finally:
        client.close()

    if exit_code != 0:
        details = err or out or f"exit code {exit_code}"
        raise VpnAgentError(details)

    return "ok"


def check_vps_internet() -> str:
    """Fixed outbound check (no arbitrary shell from callers)."""
    mode = settings.vpn_agent_mode.strip().lower()
    if mode == "ssh":
        return _check_internet_ssh()
    if mode == "local":
        return _check_internet_local()
    raise VpnAgentError(f"unsupported vpn_agent_mode: {settings.vpn_agent_mode}")


async def check_vps_internet_async() -> str:
    return await asyncio.to_thread(check_vps_internet)
