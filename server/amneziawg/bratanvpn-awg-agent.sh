#!/usr/bin/env bash
# BratanVPN — ограниченный агент AmneziaWG.
# Команды: add | remove | exists | status
# Произвольный shell извне не принимается.

set -euo pipefail

INTERFACE="${BRATANVPN_AWG_INTERFACE:-awg0}"
CONF_FILE="${BRATANVPN_AWG_CONF:-/etc/amnezia/amneziawg/awg0.conf}"
SERVER_IP="10.8.0.1"

usage() {
  cat <<'EOF'
Usage:
  bratanvpn-awg-agent.sh add <public_key> <vpn_ip>
  bratanvpn-awg-agent.sh remove <public_key>
  bratanvpn-awg-agent.sh exists <public_key>
  bratanvpn-awg-agent.sh status
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run as root"
  fi
}

validate_public_key() {
  local key="$1"
  if [[ ! "$key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    die "invalid public key format"
  fi
}

validate_vpn_ip() {
  local ip="$1"
  if [[ ! "$ip" =~ ^10\.8\.0\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
    die "invalid vpn_ip (expected 10.8.0.x)"
  fi
  if [[ "$ip" == "$SERVER_IP" || "$ip" == "10.8.0.0" || "$ip" == "10.8.0.255" ]]; then
    die "vpn_ip is not allowed: ${ip}"
  fi
}

ensure_tools() {
  command -v awg >/dev/null 2>&1 || die "awg not found"
  command -v python3 >/dev/null 2>&1 || die "python3 not found"
  [[ -f "$CONF_FILE" ]] || die "config not found: ${CONF_FILE}"
}

peer_in_runtime() {
  local key="$1"
  awg show "$INTERFACE" peers 2>/dev/null | grep -Fxq "$key"
}

peer_in_conf() {
  local key="$1"
  grep -Fq "PublicKey = ${key}" "$CONF_FILE"
}

cmd_status() {
  if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    die "interface ${INTERFACE} is down or missing"
  fi
  awg show "$INTERFACE"
  echo "OK: interface ${INTERFACE} is up"
}

cmd_exists() {
  local key="$1"
  validate_public_key "$key"
  if peer_in_runtime "$key"; then
    echo "exists: yes"
    exit 0
  fi
  echo "exists: no"
  exit 1
}

conf_add_peer() {
  local key="$1"
  local ip="$2"
  python3 - "$CONF_FILE" "$key" "$ip" <<'PY'
import sys
from pathlib import Path

conf_path = Path(sys.argv[1])
key = sys.argv[2]
ip = sys.argv[3]
text = conf_path.read_text(encoding="utf-8")
if f"PublicKey = {key}" in text:
    raise SystemExit(0)
block = (
    "\n#_bratanvpn_peer\n"
    "[Peer]\n"
    f"PublicKey = {key}\n"
    f"AllowedIPs = {ip}/32\n"
)
if not text.endswith("\n"):
    text += "\n"
conf_path.write_text(text + block, encoding="utf-8")
PY
}

conf_remove_peer() {
  local key="$1"
  python3 - "$CONF_FILE" "$key" <<'PY'
import sys
from pathlib import Path

conf_path = Path(sys.argv[1])
target = sys.argv[2]
lines = conf_path.read_text(encoding="utf-8").splitlines(keepends=True)

out = []
i = 0
n = len(lines)

while i < n:
    # Start of optional marked peer block
    if lines[i].strip() == "#_bratanvpn_peer":
        block = [lines[i]]
        i += 1
        if i < n and lines[i].strip() == "[Peer]":
            block.append(lines[i])
            i += 1
            while i < n and lines[i].strip() not in ("[Peer]", "#_bratanvpn_peer") and not (
                lines[i].startswith("[") and lines[i].strip() != "[Peer]"
            ):
                block.append(lines[i])
                i += 1
            if any(f"PublicKey = {target}" in x for x in block):
                continue
            out.extend(block)
            continue
        out.extend(block)
        continue

    if lines[i].strip() == "[Peer]":
        block = [lines[i]]
        i += 1
        while i < n and lines[i].strip() not in ("[Peer]", "#_bratanvpn_peer") and not (
            lines[i].startswith("[") and lines[i].strip() != "[Peer]"
        ):
            block.append(lines[i])
            i += 1
        if any(f"PublicKey = {target}" in x for x in block):
            continue
        out.extend(block)
        continue

    out.append(lines[i])
    i += 1

conf_path.write_text("".join(out), encoding="utf-8")
PY
}

cmd_add() {
  local key="$1"
  local ip="$2"

  validate_public_key "$key"
  validate_vpn_ip "$ip"

  awg set "$INTERFACE" peer "$key" allowed-ips "${ip}/32"
  conf_add_peer "$key" "$ip"
  echo "OK: peer added ${key} -> ${ip}/32"
}

cmd_remove() {
  local key="$1"
  validate_public_key "$key"

  if peer_in_runtime "$key"; then
    awg set "$INTERFACE" peer "$key" remove
  fi

  if peer_in_conf "$key"; then
    conf_remove_peer "$key"
  fi

  echo "OK: peer removed ${key}"
}

main() {
  require_root
  ensure_tools

  local cmd="${1:-}"
  case "$cmd" in
    status)
      cmd_status
      ;;
    exists)
      [[ $# -eq 2 ]] || die "exists requires <public_key>"
      cmd_exists "$2"
      ;;
    add)
      [[ $# -eq 3 ]] || die "add requires <public_key> <vpn_ip>"
      cmd_add "$2" "$3"
      ;;
    remove)
      [[ $# -eq 2 ]] || die "remove requires <public_key>"
      cmd_remove "$2"
      ;;
    ""|-h|--help|help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown command: ${cmd}"
      ;;
  esac
}

main "$@"
