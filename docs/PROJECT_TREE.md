# BratanVPN — дерево проекта

Актуально на: 2026-07-22

Полное дерево файлов репозитория (без секретов и артефактов сборки).

**Исключено из дерева (намеренно):**

- `.git/`
- `backend/.env`, `backend/.venv/`
- `backend/local-tunnel-test.*`
- `apps/client/build/`, `apps/client/.dart_tool/`, `windows/flutter/ephemeral/`
- `__pycache__/`, `*.egg-info/`
- `info for PROMPTING/` (локальные заметки, не в Git)

Подробное назначение каждого файла: [`ARCHITECTURE_MAP.md`](ARCHITECTURE_MAP.md)

```text
bratanvpn/
├── .cursor/
│   └── rules/
│       ├── bratanvpn.mdc
│       └── dialogue.mdc
├── .vscode/
│   └── settings.json
├── apps/
│   └── client/
│       ├── android/
│       │   ├── app/
│       │   │   ├── src/
│       │   │   │   ├── debug/
│       │   │   │   │   └── AndroidManifest.xml
│       │   │   │   ├── main/
│       │   │   │   │   ├── java/
│       │   │   │   │   │   └── io/
│       │   │   │   │   │       └── flutter/
│       │   │   │   │   │           └── plugins/
│       │   │   │   │   │               └── GeneratedPluginRegistrant.java
│       │   │   │   │   ├── kotlin/
│       │   │   │   │   │   └── com/
│       │   │   │   │   │       └── bratanvpn/
│       │   │   │   │   │           └── client/
│       │   │   │   │   │               └── MainActivity.kt
│       │   │   │   │   ├── res/
│       │   │   │   │   │   ├── drawable/
│       │   │   │   │   │   │   └── launch_background.xml
│       │   │   │   │   │   ├── drawable-v21/
│       │   │   │   │   │   │   └── launch_background.xml
│       │   │   │   │   │   ├── mipmap-hdpi/
│       │   │   │   │   │   │   └── ic_launcher.png
│       │   │   │   │   │   ├── mipmap-mdpi/
│       │   │   │   │   │   │   └── ic_launcher.png
│       │   │   │   │   │   ├── mipmap-xhdpi/
│       │   │   │   │   │   │   └── ic_launcher.png
│       │   │   │   │   │   ├── mipmap-xxhdpi/
│       │   │   │   │   │   │   └── ic_launcher.png
│       │   │   │   │   │   ├── mipmap-xxxhdpi/
│       │   │   │   │   │   │   └── ic_launcher.png
│       │   │   │   │   │   ├── values/
│       │   │   │   │   │   │   └── styles.xml
│       │   │   │   │   │   └── values-night/
│       │   │   │   │   │       └── styles.xml
│       │   │   │   │   └── AndroidManifest.xml
│       │   │   │   └── profile/
│       │   │   │       └── AndroidManifest.xml
│       │   │   └── build.gradle.kts
│       │   ├── gradle/
│       │   │   └── wrapper/
│       │   │       ├── gradle-wrapper.jar
│       │   │       └── gradle-wrapper.properties
│       │   ├── .gitignore
│       │   ├── build.gradle.kts
│       │   ├── client_android.iml
│       │   ├── gradle.properties
│       │   ├── gradlew
│       │   ├── gradlew.bat
│       │   └── settings.gradle.kts
│       ├── lib/
│       │   ├── services/
│       │   │   ├── activation_api.dart
│       │   │   └── api_config.dart
│       │   └── main.dart
│       ├── test/
│       │   └── widget_test.dart
│       ├── windows/
│       │   ├── flutter/
│       │   │   ├── CMakeLists.txt
│       │   │   ├── generated_plugin_registrant.cc
│       │   │   ├── generated_plugin_registrant.h
│       │   │   └── generated_plugins.cmake
│       │   ├── runner/
│       │   │   ├── resources/
│       │   │   │   └── app_icon.ico
│       │   │   ├── CMakeLists.txt
│       │   │   ├── flutter_window.cpp
│       │   │   ├── flutter_window.h
│       │   │   ├── main.cpp
│       │   │   ├── resource.h
│       │   │   ├── runner.exe.manifest
│       │   │   ├── Runner.rc
│       │   │   ├── utils.cpp
│       │   │   ├── utils.h
│       │   │   ├── win32_window.cpp
│       │   │   └── win32_window.h
│       │   ├── .gitignore
│       │   └── CMakeLists.txt
│       ├── .gitignore
│       ├── .metadata
│       ├── analysis_options.yaml
│       ├── client.iml
│       ├── pubspec.lock
│       ├── pubspec.yaml
│       └── README.md
├── backend/
│   ├── alembic/
│   │   ├── versions/
│   │   │   ├── 17a448b79be1_add_vpn_clients_table.py
│   │   │   ├── 7b25f5a14fc7_initial_migration.py
│   │   │   └── a3f2c8d91e04_move_vpn_fields_to_access_keys.py
│   │   ├── env.py
│   │   ├── README
│   │   └── script.py.mako
│   ├── app/
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── activation.py
│   │   │   ├── admin_keys.py
│   │   │   ├── validation.py
│   │   │   └── vpn_config.py
│   │   ├── core/
│   │   │   ├── __init__.py
│   │   │   ├── config.py
│   │   │   └── security.py
│   │   ├── db/
│   │   │   ├── __init__.py
│   │   │   ├── base.py
│   │   │   ├── init_db.py
│   │   │   └── session.py
│   │   ├── models/
│   │   │   ├── access_key.py
│   │   │   └── enums.py
│   │   ├── services/
│   │   │   ├── __init__.py
│   │   │   ├── access_key_service.py
│   │   │   ├── activation_service.py
│   │   │   ├── vpn_agent_client.py
│   │   │   └── vpn_service.py
│   │   ├── __init__.py
│   │   └── main.py
│   ├── .env.example
│   ├── alembic.ini
│   └── pyproject.toml
├── docs/
│   ├── ACCESS_KEY_HASHING_DEFERRED.md
│   ├── ARCHITECTURE_MAP.md
│   ├── BratanVPN_security.xlsx
│   ├── BratanVPN_speed_compare.xlsx
│   ├── BratanVPN_status.xlsx
│   ├── CHATGPT_PROJECT_CONTEXT.md
│   └── PROJECT_TREE.md
├── infrastructure/
├── server/
│   └── amneziawg/
│       ├── bratanvpn-awg-agent.sh
│       └── README.md
├── .gitignore
├── docker-compose.yml
└── README.md
```
