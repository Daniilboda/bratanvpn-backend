# BratanVPN — карта архитектуры проекта

Документ описывает **назначение каждой папки и файла** в монорепозитории, а также пометки:

- **создан фреймворком (имя) — не требовал изменений**
- **создан фреймворком (имя) — требовал изменений** (+ что изменено)
- **создан вручную / проектом BratanVPN**

Дата составления: 2026-07-22  
Репозиторий: `https://github.com/Daniilboda/bratanvpn-backend.git`

**Дерево проекта (обязательный артефакт):** [`PROJECT_TREE.md`](PROJECT_TREE.md)

---

## 1. Общая схема системы

```text
┌─────────────────────┐     HTTPS/HTTP (dev)      ┌──────────────────────┐
│  Flutter-клиент     │ ───────────────────────► │  FastAPI backend     │
│  apps/client        │ ◄─────────────────────── │  backend/app         │
│  Windows / Android  │   JSON REST API          │  PostgreSQL          │
└─────────┬───────────┘                          └──────────┬───────────┘
          │                                                 │
          │ (будущее: нативный VPN)                         │ SSH (dev) / local (prod)
          ▼                                                 ▼
┌─────────────────────┐                          ┌──────────────────────┐
│ AmneziaWG туннель   │ ◄──── add/remove peer ───│ bratanvpn-awg-agent  │
│ на устройстве       │                          │ на Ubuntu VPS        │
└─────────────────────┘                          └──────────────────────┘
```

**Важно:** backend **не** пропускает пользовательский VPN-трафик. Он только управляет ключами доступа и peer’ами на VPN-сервере.

---

## 2. Дерево проекта (полное)

Полное дерево **с кратким описанием каждого файла** — в [`PROJECT_TREE.md`](PROJECT_TREE.md).

Ниже — компактная копия структуры (без длинных описаний). Актуальные описания всегда смотри в `PROJECT_TREE.md`.

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

### 2.1. Назначение папок верхнего уровня

| Путь | Назначение |
|------|------------|
| `apps/` | Клиентские приложения (сейчас только Flutter) |
| `backend/` | FastAPI API, SQLAlchemy, Alembic, настройки |
| `server/` | Скрипты/агенты для хоста VPS (AmneziaWG) |
| `docs/` | Документация, статусы, security/speed таблицы, дерево проекта |
| `infrastructure/` | Зарезервировано под compose/env (пока пусто; compose лежит в корне) |
| `.cursor/rules/` | Правила для AI/разработки в Cursor |
| `docker-compose.yml` | Локальный PostgreSQL |
| `README.md` | Краткое описание репозитория |
| `.gitignore` | Исключения Git (секреты, venv, build) |

**Не в Git (и не должны попадать):**

| Путь | Почему |
|------|--------|
| `backend/.env` | Секреты (ADMIN_API_KEY, SSH password и т.д.) |
| `backend/.venv/` | Виртуальное окружение Python |
| `backend/local-tunnel-test.*` | Тестовый туннель с private key |
| `apps/client/build/`, `.dart_tool/` | Артефакты сборки Flutter |
| `info for PROMPTING/` | Локальные заметки/секреты VPS — **не коммитить** |

---

## 3. Корень репозитория

### `README.md`
**Создан вручную / проектом.** Краткое описание репозитория на GitHub.

### `docker-compose.yml`
**Создан вручную / проектом.** Сервис `postgres:16`, контейнер `bratanvpn-postgres`, порт хоста **5433→5432**, volume `postgres_data`.

### `.gitignore`
**Создан вручную / проектом.** Игнорирует `.env`, venv, кэши, `local-tunnel-test.*`, `_tmp_*.py`.

### `.vscode/settings.json`
**Создан IDE (VS Code / Cursor).** Локальные настройки редактора. В корневом `.gitignore` указан `.vscode/` — обычно не коммитится.

---

## 4. `.cursor/rules/`

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `bratanvpn.mdc` | Целевая спецификация MVP: стек, API, дизайн, безопасность, критерии готовности | **Создан проектом.** Неоднократно обновлялся (в т.ч. §12 дизайн: чёрный фон, кнопка power, Франция, таймер) |
| `dialogue.mdc` | Правила диалога с AI: пользователь пишет код сам, AI правит только по просьбе | **Создан проектом** |

---

## 5. `docs/`

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `ARCHITECTURE_MAP.md` | Этот документ — карта папок/файлов | **Создан проектом** |
| `PROJECT_TREE.md` | Полное дерево файлов репозитория | **Создан проектом** |
| `CHATGPT_PROJECT_CONTEXT.md` | Контекст проекта для внешних AI / онбординг | **Создан проектом** |
| `ACCESS_KEY_HASHING_DEFERRED.md` | Решение: хэш access key отложен до прода | **Создан проектом** |
| `BratanVPN_status.xlsx` | Трекер задач MVP (сделано / осталось) | **Создан проектом**, периодически обновляется |
| `BratanVPN_speed_compare.xlsx` | Сравнение скорости VPN / серверов | **Создан проектом** |
| `BratanVPN_security.xlsx` | Аудит безопасности, Argon2 vs HMAC, backlog | **Создан проектом** |

---

## 6. `server/amneziawg/`

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `bratanvpn-awg-agent.sh` | Ограниченный агент на VPS: `add` / `remove` / `exists` / `status` peer в AmneziaWG. Без произвольного shell | **Создан проектом.** Устанавливается на VPS как `/usr/local/sbin/bratanvpn-awg-agent` |
| `README.md` | Как пользоваться агентом | **Создан проектом** |

---

## 7. `backend/` — FastAPI

### 7.1. Конфиг и метаданные

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `pyproject.toml` | Имя пакета, зависимости (FastAPI, SQLAlchemy, paramiko…), pytest/ruff | **Создан проектом** |
| `alembic.ini` | Конфиг Alembic (миграции БД) | **Создан фреймворком Alembic — требовал изменений** (url/настройки под проект, связка с `env.py`) |
| `.env.example` | Пример переменных окружения без секретов | **Создан проектом** |
| `.env` | Реальные секреты локально | **Создан локально — НЕ в Git** |

### 7.2. `alembic/`

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `env.py` | Окружение миграций: metadata моделей, async URL | **Создан фреймворком Alembic — требовал изменений** (подключение к `Base.metadata`, async engine проекта) |
| `script.py.mako` | Шаблон новой миграции | **Создан фреймворком Alembic — не требовал изменений** |
| `README` | Справка Alembic | **Создан фреймворком Alembic — не требовал изменений** |
| `versions/7b25f5a14fc7_initial_migration.py` | Начальная схема | **Создан Alembic (autogenerate/ручная правка) — проектная миграция** |
| `versions/17a448b79be1_add_vpn_clients_table.py` | Историческая миграция vpn_clients (позже снята) | **Проектная миграция** |
| `versions/a3f2c8d91e04_move_vpn_fields_to_access_keys.py` | VPN-поля на `access_keys`, drop `vpn_clients` | **Проектная миграция** |

### 7.3. `app/` — код API

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `main.py` | Точка входа FastAPI, подключение роутеров | **Создан проектом** |
| `__init__.py` (и в подпакетах) | Пакет Python | **Создан проектом** |

#### `app/api/`

| Файл | Назначение |
|------|------------|
| `activation.py` | `POST /api/v1/activate` — активация ключа + device + vpn_public_key |
| `admin_keys.py` | Admin CRUD/revoke/restore ключей (`X-Admin-Key`) |
| `validation.py` | Валидация access key (user API) |
| `vpn_config.py` | `GET /api/v1/vpn/config` — выдача конфига AmneziaWG клиенту |

Все **созданы проектом**. Pydantic-модели запросов лежат рядом с роутерами (отдельной папки `schemas/` нет).

#### `app/core/`

| Файл | Назначение |
|------|------------|
| `config.py` | `Settings` / pydantic-settings: DB URL, VPN params, agent SSH |
| `security.py` | Проверка admin API key |

**Созданы проектом.**

#### `app/db/`

| Файл | Назначение |
|------|------------|
| `base.py` | SQLAlchemy `DeclarativeBase` |
| `session.py` | Async session / engine |
| `init_db.py` | Инициализация / импорт моделей |

**Созданы проектом.**

#### `app/models/`

| Файл | Назначение |
|------|------------|
| `access_key.py` | Модель `AccessKey`: key, status, device_id, vpn_public_key, vpn_ip |
| `enums.py` | Перечисления статусов (если используются) |

**Созданы проектом.** Схема MVP (зафиксирована): **1 access key = 1 устройство** (без отдельной таблицы Device). Статусы: `created` / `activated` / `revoked`.

#### `app/services/`

| Файл | Назначение |
|------|------------|
| `access_key_service.py` | Генерация/CRUD/validate/revoke/restore ключей |
| `activation_service.py` | Логика активации + вызов агента `add_peer` |
| `vpn_service.py` | Выделение `vpn_ip`, сборка ответа конфига |
| `vpn_agent_client.py` | Клиент агента: SSH (dev) / local (prod), валидация pubkey/ip |

**Созданы проектом.**

---

## 8. `apps/client/` — Flutter-клиент

Создан командой:

```bash
flutter create --org com.bratanvpn --platforms=android,windows client
```

### 8.1. Корень Flutter-проекта

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `pubspec.yaml` | Имя пакета, зависимости | **Создан Flutter — требовал изменений:** добавлен `http: ^1.2.2` |
| `pubspec.lock` | Зафиксированные версии пакетов | **Создан Flutter / `flutter pub get` — обновлялся** при добавлении `http` |
| `analysis_options.yaml` | Линты (`flutter_lints`) | **Создан Flutter — не требовал изменений** (пока) |
| `README.md` | Шаблонный README приложения | **Создан Flutter — не требовал изменений** (пока) |
| `.metadata` | Метаданные Flutter tool | **Создан Flutter — не требовал изменений** |
| `.gitignore` | Игнор build/`.dart_tool` | **Создан Flutter — не требовал изменений** |
| `client.iml` | Модуль IntelliJ/Android Studio | **Создан IDE/Flutter — обычно не важен для логики** |

### 8.2. `lib/` — код приложения (Dart)

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `main.dart` | UI: главный экран, диалог ключа, таймер, настройки | **Создан Flutter (демо-счётчик) — требовал изменений:** полностью заменён на BratanVPN UI + активация |
| `services/api_config.dart` | `apiBaseUrl` | **Создан проектом** |
| `services/activation_api.dart` | HTTP `POST /api/v1/activate`, ошибки | **Создан проектом** |
| `services/vpn_keypair.dart` | X25519 keypair (base64) | **Создан проектом** |
| `services/secure_vault.dart` | device id, VPN keys, activation в secure storage | **Создан проектом** |

### 8.3. `test/`

| Файл | Назначение | Происхождение |
|------|------------|---------------|
| `widget_test.dart` | Widget-тесты UI/активации (fake API) | **Создан Flutter (тест счётчика) — требовал изменений:** переписан под BratanVPN |

### 8.4. `android/` — нативная оболочка Android

| Путь | Назначение | Происхождение |
|------|------------|---------------|
| `settings.gradle.kts` | Настройки Gradle multi-project | **Создан Flutter — не требовал изменений** |
| `build.gradle.kts` | Корневой Gradle Android | **Создан Flutter — не требовал изменений** |
| `gradle.properties` | Свойства Gradle | **Создан Flutter — не требовал изменений** |
| `gradle/wrapper/*` | Gradle Wrapper | **Создан Flutter — не требовал изменений** |
| `gradlew`, `gradlew.bat` | Скрипты Gradle | **Создан Flutter — не требовал изменений** |
| `.gitignore` | Игнор Android build / local.properties | **Создан Flutter — не требовал изменений** |
| `local.properties` | Локальный путь SDK | **Создан Android Studio/Flutter локально — не в Git** |
| `app/build.gradle.kts` | Модуль приложения, applicationId | **Создан Flutter — не требовал изменений** (package `com.bratanvpn.client` задан через `--org` при create) |
| `app/src/main/AndroidManifest.xml` | Манифест, MainActivity, launcher | **Создан Flutter — не требовал изменений** (пока; позже VPN permissions) |
| `app/src/debug/AndroidManifest.xml` | Debug-манифест | **Создан Flutter — не требовал изменений** |
| `app/src/profile/AndroidManifest.xml` | Profile-манифест | **Создан Flutter — не требовал изменений** |
| `app/src/main/kotlin/.../MainActivity.kt` | Точка входа Android (`FlutterActivity`) | **Создан Flutter — не требовал изменений** (позже VpnService) |
| `app/src/main/java/.../GeneratedPluginRegistrant.java` | Регистрация плагинов | **Создан Flutter — генерируется/обновляется tool’ом** |
| `app/src/main/res/mipmap-*/ic_launcher.png` | Иконки приложения | **Создан Flutter — не требовал изменений** |
| `app/src/main/res/drawable*/launch_background.xml` | Splash/launch background | **Создан Flutter — не требовал изменений** |
| `app/src/main/res/values/styles.xml` | Темы | **Создан Flutter — не требовал изменений** |
| `app/src/main/res/values-night/styles.xml` | Night-темы | **Создан Flutter — не требовал изменений** |

### 8.5. `windows/` — нативная оболочка Windows

| Путь | Назначение | Происхождение |
|------|------------|---------------|
| `CMakeLists.txt` | Корневой CMake Windows | **Создан Flutter — не требовал изменений** |
| `.gitignore` | Игнор ephemeral/build | **Создан Flutter — не требовал изменений** |
| `flutter/CMakeLists.txt` | CMake сборки Flutter engine | **Создан Flutter — не требовал изменений** |
| `flutter/generated_plugin_registrant.*` | Регистрация плагинов C++ | **Создан Flutter — генерируется tool’ом** |
| `flutter/generated_plugins.cmake` | Список плагинов | **Создан Flutter — генерируется tool’ом** |
| `flutter/ephemeral/` | Кэш/артефакты engine | **Создан Flutter — не в Git** |
| `runner/main.cpp` | `wWinMain`, создание окна | **Создан Flutter — требовал изменений:** размер окна `380×680`, заголовок `BratanVPN` (вместо 1280×720 / `client`) |
| `runner/flutter_window.cpp` / `.h` | Окно + Flutter view | **Создан Flutter — не требовал изменений** |
| `runner/win32_window.cpp` / `.h` | Win32-обёртка окна | **Создан Flutter — не требовал изменений** |
| `runner/utils.cpp` / `.h` | Утилиты консоли/аргументов | **Создан Flutter — не требовал изменений** |
| `runner/CMakeLists.txt` | CMake runner | **Создан Flutter — не требовал изменений** |
| `runner/Runner.rc`, `resource.h`, `runner.exe.manifest` | Ресурсы/манифест exe | **Создан Flutter — не требовал изменений** |
| `runner/resources/app_icon.ico` | Иконка приложения | **Создан Flutter — не требовал изменений** |

---

## 9. Потоки данных (как связано)

### 9.1. Активация (текущий MVP-путь)

```text
Flutter UI (main.dart)
  → ActivationApi.activate()
  → POST /api/v1/activate
  → activation_service.activate_access_key()
  → allocate vpn_ip + save pubkey
  → vpn_agent_client.add_peer()  →  SSH → bratanvpn-awg-agent.sh add
  → ответ { vpn_ip }
  → UI: «Подключено» (туннель из приложения пока не поднимается)
```

### 9.2. Что ещё не подключено в клиенте

- `GET /vpn/config` из Flutter + сохранение конфига в vault  
- Нативный AmneziaWG connect/disconnect  
- Периодический `POST /validate` / проверка отзыва  
- Хэш access key в БД (отложено — см. `ACCESS_KEY_HASHING_DEFERRED.md`)

**Не долг MVP:** отдельные Device / статусы `active|blocked|expired` / API `/activation`+`/devices/*` — текущая схема (`created|activated|revoked`, 1 ключ = 1 устройство, `/activate`) зафиксирована в `.cursor/rules/bratanvpn.mdc`.

---

## 10. Сводка пометки «фреймворк»

| Фреймворк / инструмент | Где | Суть |
|------------------------|-----|------|
| **Flutter** | `apps/client/**` (кроме `lib/services/*` и переписанного UI/тестов) | Каркас android/windows/pubspec |
| **Flutter — с правками** | `lib/main.dart`, `test/widget_test.dart`, `pubspec.yaml` (+http), `windows/runner/main.cpp` | UI BratanVPN, API, размер окна |
| **Alembic** | `backend/alembic/**` | Миграции; `env.py`/`alembic.ini` адаптированы |
| **FastAPI / SQLAlchemy** | не генерируют дерево файлов сами | Весь `backend/app` написан проектом |
| **Docker Compose** | `docker-compose.yml` | Написан проектом |

---

## 11. Как читать этот документ дальше

При добавлении файла:

1. Вписать путь в нужный раздел.  
2. Указать назначение одной фразой.  
3. Пометить: проект / фреймворк без правок / фреймворк с правками (+ список правок).

Связанные документы:

- Дерево проекта: `PROJECT_TREE.md`
- Статус задач: `BratanVPN_status.xlsx`
- Безопасность: `BratanVPN_security.xlsx`
- Скорость: `BratanVPN_speed_compare.xlsx`
- Контекст AI: `CHATGPT_PROJECT_CONTEXT.md`
