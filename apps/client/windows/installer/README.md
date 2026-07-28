# BratanVPN Windows installer (Inno Setup)

Produces `BratanVPN-Setup-*.exe` that installs into `C:\Program Files\BratanVPN`,
creates Start Menu (+ optional Desktop) shortcuts, and cleans the helper service on uninstall.

## Prerequisites

1. [Flutter](https://docs.flutter.dev/) (Windows desktop enabled)
2. [Go](https://go.dev/) — to build `bratanvpn_helper.exe`
3. AmneziaWG sidecar: run `..\amneziawg\sync_from_install.ps1`
4. [Inno Setup 6](https://jrsoftware.org/isinfo.php) (`ISCC.exe`)

## Build

From this folder:

```powershell
.\build_installer.ps1
```

Or with a custom API URL:

```powershell
.\build_installer.ps1 -ApiBaseUrl "https://api.bratanvpn.com"
```

Skip Flutter rebuild if Release is already fresh:

```powershell
.\build_installer.ps1 -SkipFlutterBuild
```

Output:

```text
apps/client/build/installer/BratanVPN-Setup-1.0.0.exe
```

## What the user gets

* Installer wizard (Russian)
* Fixed path: `C:\Program Files\BratanVPN` (no folder picker)
* `BratanVPN.exe` + helper + AmneziaWG sidecar
* Start Menu shortcut; Desktop shortcut (checked by default)
* Uninstall removes the `BratanVpnHelper` Windows service

First VPN connect may still show one UAC prompt to register the helper service.
