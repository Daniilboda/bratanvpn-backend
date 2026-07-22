# BratanVPN — дерево проекта (с описаниями)

Актуально на: 2026-07-22

Полное дерево файлов репозитория. У каждого файла — **краткое назначение**.

**Исключено:** `.git/`, `.env`, `.venv/`, `build/`, `.dart_tool/`, `ephemeral/`, `__pycache__/`, `local-tunnel-test.*`, `info for PROMPTING/`.

Подробный разбор и пометки фреймворков: [`ARCHITECTURE_MAP.md`](ARCHITECTURE_MAP.md)

---

```text
bratanvpn/                                          — корень монорепозитория BratanVPN
├── .cursor/
│   └── rules/                                      — правила для Cursor AI
│       ├── bratanvpn.mdc                           — целевая спецификация MVP (стек, API, дизайн)
│       └── dialogue.mdc                            — правила совместной работы с AI
├── .vscode/
│   └── settings.json                               — локальные настройки редактора
├── apps/                                           — клиентские приложения
│   └── client/                                     — Flutter-клиент (Windows + Android)
│       ├── android/                                — нативная оболочка Android (Flutter)
│       │   ├── app/
│       │   │   ├── src/
│       │   │   │   ├── debug/
│       │   │   │   │   └── AndroidManifest.xml     — манифест debug-сборки
│       │   │   │   ├── main/
│       │   │   │   │   ├── java/.../GeneratedPluginRegistrant.java — регистрация Flutter-плагинов
│       │   │   │   │   ├── kotlin/.../MainActivity.kt — точка входа Android (FlutterActivity)
│       │   │   │   │   ├── res/
│       │   │   │   │   │   ├── drawable/launch_background.xml — фон splash
│       │   │   │   │   │   ├── drawable-v21/launch_background.xml — splash для API 21+
│       │   │   │   │   │   ├── mipmap-*/ic_launcher.png — иконки приложения
│       │   │   │   │   │   ├── values/styles.xml   — темы Material
│       │   │   │   │   │   └── values-night/styles.xml — night-темы
│       │   │   │   │   └── AndroidManifest.xml     — основной манифест приложения
│       │   │   │   └── profile/
│       │   │   │       └── AndroidManifest.xml     — манифест profile-сборки
│       │   │   └── build.gradle.kts                — Gradle-модуль app (applicationId)
│       │   ├── gradle/wrapper/                     — Gradle Wrapper
│       │   │   ├── gradle-wrapper.jar
│       │   │   └── gradle-wrapper.properties       — версия Gradle
│       │   ├── .gitignore                          — игнор Android build / local.properties
│       │   ├── build.gradle.kts                    — корневой Gradle Android
│       │   ├── client_android.iml                  — модуль IDE
│       │   ├── gradle.properties                   — свойства Gradle
│       │   ├── gradlew / gradlew.bat               — скрипты запуска Gradle
│       │   └── settings.gradle.kts                 — multi-project settings
│       ├── lib/                                    — Dart-код приложения (основная логика UI)
│       │   ├── services/
│       │   │   ├── activation_api.dart             — HTTP POST /api/v1/activate + ошибки
│       │   │   └── api_config.dart                 — base URL API и stub device_id
│       │   └── main.dart                           — UI: кнопка, диалог ключа, таймер, настройки
│       ├── test/
│       │   └── widget_test.dart                    — widget-тесты UI и активации
│       ├── windows/                                — нативная оболочка Windows (Flutter)
│       │   ├── flutter/
│       │   │   ├── CMakeLists.txt                  — CMake Flutter engine (Windows)
│       │   │   ├── generated_plugin_registrant.cc/.h — авторегистрация плагинов C++
│       │   │   └── generated_plugins.cmake         — список плагинов для CMake
│       │   ├── runner/
│       │   │   ├── resources/app_icon.ico          — иконка .exe
│       │   │   ├── CMakeLists.txt                  — сборка runner
│       │   │   ├── flutter_window.cpp/.h           — окно + Flutter view
│       │   │   ├── main.cpp                        — wWinMain; размер окна BratanVPN 380×680
│       │   │   ├── resource.h / Runner.rc          — ресурсы Windows
│       │   │   ├── runner.exe.manifest             — манифест исполняемого файла
│       │   │   ├── utils.cpp/.h                    — утилиты консоли/argv
│       │   │   └── win32_window.cpp/.h             — Win32-обёртка окна
│       │   ├── .gitignore
│       │   └── CMakeLists.txt                      — корневой CMake Windows
│       ├── .gitignore                              — игнор build / .dart_tool
│       ├── .metadata                               — метаданные Flutter tool
│       ├── analysis_options.yaml                   — правила анализатора Dart
│       ├── client.iml                              — модуль IDE
│       ├── pubspec.lock                            — зафиксированные версии пакетов
│       ├── pubspec.yaml                            — зависимости Flutter (+ http)
│       └── README.md                               — README шаблона Flutter
├── backend/                                        — FastAPI backend
│   ├── alembic/                                    — миграции БД
│   │   ├── versions/                               — история миграций
│   │   │   ├── 7b25f5a14fc7_initial_migration.py   — начальная схема
│   │   │   ├── 17a448b79be1_add_vpn_clients_table.py — (история) таблица vpn_clients
│   │   │   └── a3f2c8d91e04_move_vpn_fields_to_access_keys.py — VPN-поля на access_keys
│   │   ├── env.py                                  — окружение Alembic + metadata моделей
│   │   ├── README                                  — справка Alembic
│   │   └── script.py.mako                          — шаблон новой миграции
│   ├── app/                                        — код API
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── activation.py                       — POST /activate
│   │   │   ├── admin_keys.py                       — admin API ключей
│   │   │   ├── validation.py                       — валидация access key
│   │   │   └── vpn_config.py                       — GET /vpn/config
│   │   ├── core/
│   │   │   ├── __init__.py
│   │   │   ├── config.py                           — Settings (.env): DB, VPN, agent SSH
│   │   │   └── security.py                         — проверка X-Admin-Key
│   │   ├── db/
│   │   │   ├── __init__.py
│   │   │   ├── base.py                             — SQLAlchemy DeclarativeBase
│   │   │   ├── init_db.py                          — импорт моделей / init
│   │   │   └── session.py                          — async engine и session
│   │   ├── models/
│   │   │   ├── access_key.py                       — модель AccessKey (1 ключ = 1 устройство)
│   │   │   └── enums.py                            — enum статусов
│   │   ├── services/
│   │   │   ├── __init__.py
│   │   │   ├── access_key_service.py               — create/list/revoke/restore/validate
│   │   │   ├── activation_service.py               — активация + add_peer
│   │   │   ├── vpn_agent_client.py                 — SSH/local вызов awg-агента
│   │   │   └── vpn_service.py                      — allocate IP, сборка конфига
│   │   ├── __init__.py
│   │   └── main.py                                 — точка входа FastAPI, роутеры
│   ├── .env.example                                — пример env без секретов
│   ├── alembic.ini                                 — конфиг Alembic
│   └── pyproject.toml                              — зависимости Python-проекта
├── docs/                                           — документация
│   ├── ACCESS_KEY_HASHING_DEFERRED.md              — хэш ключей отложен до прода
│   ├── ARCHITECTURE_MAP.md                         — карта архитектуры + описания файлов
│   ├── PROJECT_TREE.md                             — это дерево с краткими описаниями
│   ├── BratanVPN_security.xlsx                     — аудит безопасности
│   ├── BratanVPN_speed_compare.xlsx                — сравнение скорости VPN/серверов
│   ├── BratanVPN_status.xlsx                       — трекер задач MVP
│   └── CHATGPT_PROJECT_CONTEXT.md                  — контекст проекта для AI
├── infrastructure/                                 — зарезервировано под infra (пока пусто)
├── server/
│   └── amneziawg/
│       ├── bratanvpn-awg-agent.sh                  — агент add/remove/exists/status на VPS
│       └── README.md                               — инструкция по агенту
├── .gitignore                                      — что не коммитить
├── docker-compose.yml                              — локальный PostgreSQL :5433
└── README.md                                       — описание репозитория на GitHub
```

## Легенда пометок (см. ARCHITECTURE_MAP.md)

- Файлы под `android/`, `windows/` (кроме `runner/main.cpp`) в основном: **созданы Flutter — без правок** (пока).
- `lib/main.dart`, `test/widget_test.dart`, `pubspec.yaml`, `windows/runner/main.cpp`: **созданы Flutter — с правками**.
- `lib/services/*`, почти весь `backend/app`, `server/amneziawg`: **созданы проектом**.
