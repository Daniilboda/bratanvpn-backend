# AmneziaWG sidecar (bundled with BratanVPN Windows build)

Пользователь **не** ставит AmneziaWG отдельно: бинарники копируются рядом с `client.exe` при сборке.

```text
client.exe
bratanvpn_helper.exe          ← служба (UAC один раз), см. ../helper/
amneziawg/
  amneziawg.exe
  wintun.dll
  awg.exe
```

## Подготовка (один раз у разработчика)

1. Установи MSI с https://github.com/amnezia-vpn/amneziawg-windows-client/releases  
   (нужен только как источник файлов для копирования).
2. Скопируй бинарники в эту папку:

```powershell
cd apps\client\windows\amneziawg
.\sync_from_install.ps1
```

3. Собери helper:

```powershell
cd apps\client\windows\helper
.\build_helper.ps1
```

`*.exe` / `*.dll` в git **не** коммитятся.

## Права (UAC)

Первое «Подключиться» может показать **один** UAC — установка службы `BratanVpnHelper`.  
Дальше подключение/отключение без повышения прав (named pipe → helper → amneziawg).
