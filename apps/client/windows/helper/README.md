# BratanVPN Windows tunnel helper

Privileged Windows service that starts/stops the AmneziaWG tunnel.

## Why

`amneziawg /installtunnelservice` needs admin. Without a helper, every
Подключиться / Отключиться would show UAC.

Flow:

1. First VPN connect → Flutter elevates **once** (`bratanvpn_helper.exe install`) → UAC.
2. Helper copies AmneziaWG + itself into `C:\ProgramData\BratanVPN\` and registers service `BratanVpnHelper`.
3. Later start/stop → Flutter talks to named pipe `\\.\pipe\BratanVpnHelper` (no UAC).

## Build (developer)

```powershell
cd apps\client\windows\helper
.\build_helper.ps1
```

Requires [Go](https://go.dev/dl/). Output: `bratanvpn_helper.exe` (gitignored).

Also need AmneziaWG sidecar: `..\amneziawg\sync_from_install.ps1`.

Then:

```powershell
cd apps\client
flutter run -d windows --dart-define=API_BASE_URL=https://api.bratanvpn.com
```

## Manual install / uninstall (elevated)

```powershell
.\bratanvpn_helper.exe install
.\bratanvpn_helper.exe uninstall
```

## Pipe protocol

```text
PING   → PONG
STATUS → RUNNING | STOPPED
START C:\path\to\bratanvpn.conf → OK | ERR ...
STOP   → OK | ERR ...
```
