# BratanVPN — полный контекст проекта для ChatGPT / AI-ассистента

> **Назначение файла:** источник правды о проекте для внешней LLM.
> Перед любой задачей: (1) прочитай этот файл и `.cursor/rules/bratanvpn.mdc`, (2) **текущая схема MVP зафиксирована** (статусы `created|activated|revoked`, 1 ключ = 1 устройство, API `/activate` и `/admin/keys`) — не «чинить» её под старую спеку без запроса, (3) не выдумывай эндпоинты, модели и файлы, которых здесь нет.
>
> **Дата снимка состояния:** 2026-07-23  
> **Репозиторий:** `bratanvpn` (монорепозиторий, Windows-разработка)  
> **Стадия:** backend + агент AmneziaWG + Flutter UI/активация/keypair/vault; нативный туннель ещё нет.

---

## 0. Как работать с этим проектом (инструкция для AI)

1. **Сначала смотри раздел «ТЕКУЩЕЕ СОСТОЯНИЕ»** — это то, что реально есть в git/коде.
2. **Спека** `.cursor/rules/bratanvpn.mdc` обновлена под текущую схему MVP (2026-07-23). Не предлагай Device / `active|blocked|expired` / `/devices/*` как обязательный рефакторинг.
3. Не ломай работающие activate/validate/admin keys/vpn config без явной причины.
4. Не добавляй фичи вне MVP (оплаты, iOS, Redis, Kubernetes, рефералка, аналитика и т.д.) — см. запреты.
5. Не храни секреты в коде. Не логируй приватные VPN-ключи и plaintext access keys (в логах).
6. При изменении БД — делай Alembic-миграцию.
7. При критической логике — добавляй pytest.
8. Отвечай / планируй в формате:
   1. Что будет сделано  
   2. Какие файлы изменятся  
   3. Реализация  
   4. Как запустить  
   5. Как проверить  
   6. Ограничения текущего решения  

---

## 1. Что такое BratanVPN (продукт)

**BratanVPN** — VPN-сервис с ручной выдачей индивидуальных ключей доступа (не публичная подписка с оплатой в v1).

### Роли

| Роль | Что делает |
|------|------------|
| Администратор | Создаёт ключ, передаёт пользователю лично, отзывает/восстанавливает ключи |
| Пользователь | Вводит ключ в приложении (Windows / Android), активирует на своём устройстве (1 ключ = 1 device), подключается к VPN одной кнопкой |
| Backend (FastAPI) | Проверяет ключи, активирует, выдаёт VPN-конфиг, управляет доступом. **Не пропускает пользовательский VPN-трафик через себя** |
| VPN-сервер (AmneziaWG 2.0 на Ubuntu VPS) | Туннель, маршрутизация, peer public keys, firewall |

### Ключевой принцип безопасности

- Access key (типа `BRTN-...`) — **не** приватный ключ VPN.
- Пара VPN-ключей создаётся **на устройстве**.
- **Приватный VPN-ключ никогда:** не уходит на backend, не пишется в PostgreSQL, не логируется, не отдаётся админу.
- Backend хранит только **публичный** VPN-ключ устройства.

---

## 2. ТЕКУЩЕЕ СОСТОЯНИЕ РЕПОЗИТОРИЯ (факт на 2026-07-19)

### 2.1. Что есть / чего нет

| Путь | Статус |
|------|--------|
| `backend/` | **Есть** — рабочий прототип API ключей |
| `docker-compose.yml` (корень) | **Есть** — только PostgreSQL |
| `.cursor/rules/bratanvpn.mdc` | **Есть** — полная целевая спека |
| `.gitignore` | **Есть** |
| `docs/` | Папка **пустая** (кроме этого файла) |
| `server/` | Папка **пустая** |
| `infrastructure/` | Папка **пустая** |
| `apps/` / Flutter-клиент | **Отсутствует** |
| Root `README.md` | **Отсутствует** |
| `backend/tests/` | **Отсутствует** |
| `backend/Dockerfile` | **Отсутствует** |
| Admin CLI (`python -m app.admin`) | **Отсутствует** |
| Caddy / AmneziaWG scripts / monitoring | **Отсутствуют** |

### 2.2. Фактическое дерево backend (важное)

```text
bratanvpn/
├── .cursor/rules/bratanvpn.mdc          # целевые правила проекта
├── .gitignore
├── docker-compose.yml                   # только postgres
├── docs/
│   └── CHATGPT_PROJECT_CONTEXT.md       # этот файл
├── infrastructure/                      # пусто
├── server/                              # пусто
└── backend/
    ├── .env.example
    ├── alembic.ini
    ├── pyproject.toml
    ├── alembic/
    │   ├── env.py
    │   └── versions/
│       ├── 7b25f5a14fc7_initial_migration.py
│       ├── 17a448b79be1_add_vpn_clients_table.py
│       └── a3f2c8d91e04_move_vpn_fields_to_access_keys.py
    └── app/
        ├── main.py
        ├── api/
        │   ├── activation.py
        │   ├── admin_keys.py
        │   └── validation.py
        ├── core/
        │   ├── config.py
        │   └── security.py
        ├── db/
        │   ├── base.py
        │   ├── init_db.py
        │   └── session.py
        ├── models/
        │   ├── access_key.py
        │   └── enums.py
        └── services/
            ├── access_key_service.py
            ├── activation_service.py
            └── vpn_service.py             # allocate_ip + assign_vpn; НЕ подключён к API
```

Папки `app/schemas/` **нет**. Pydantic-схемы лежат рядом с эндпоинтами в `app/api/`.

### 2.3. Стек текущего backend

- Python `>=3.13`
- FastAPI + Uvicorn
- Pydantic v2 + pydantic-settings
- SQLAlchemy 2 **async** + asyncpg
- Alembic (в optional `dev`)
- PostgreSQL 16 (Docker)

**Зависимости** (`backend/pyproject.toml`):

```text
fastapi, uvicorn[standard], pydantic, pydantic-settings, sqlalchemy, asyncpg
dev: pytest, httpx, ruff, alembic
```

Нет: bcrypt/argon2, rate limiting, Redis, JWT-библиотек.

---

## 3. ТЕКУЩИЙ API (реализовано точно так)

Базовый prefix: `/api/v1`  
Приложение: `backend/app/main.py`

### 3.1. Пользовательские (без авторизации)

#### `POST /api/v1/activate`

Файл: `backend/app/api/activation.py`

Request:

```json
{
  "access_key": "BRATAN-...",
  "device_id": "some-device-id"
}
```

Поведение (`activation_service.activate_access_key`):

| Результат | HTTP | detail |
|-----------|------|--------|
| ключ не найден | 404 | Access key not found |
| уже активирован на этом device_id | 409 | Access key is already activated on this device |
| активирован на другом device_id | 403 | Access key is activated on another device |
| успех | 200 | `{"message": "Access key activated successfully"}` |

Что делает при успехе:

- `status = "activated"`
- `device_id = <переданный>`

Чего **не** делает:

- не проверяет `revoked` явно перед активацией (если статус не `"activated"`, просто активирует — в т.ч. потенциально revoked)
- не принимает VPN public key
- не заполняет `vpn_public_key` / `vpn_ip`
- не выдаёт VPN-конфиг
- не создаёт device token

#### `POST /api/v1/validate`

Файл: `backend/app/api/validation.py`  
Router prefix: `/validate` → полный путь `POST /api/v1/validate`

Request:

```json
{
  "key": "BRATAN-...",
  "device_id": "some-device-id"
}
```

Response:

```json
{ "status": "<строка>" }
```

Возможные `status` (`access_key_service.validate_access_key`):

| status | Когда |
|--------|--------|
| `not_found` | ключа нет |
| `revoked` | статус revoked |
| `ready_to_activate` | статус created |
| `device_mismatch` | activated, но другой device_id |
| `valid` | activated и device_id совпал |

### 3.2. Админские (заголовок `X-Admin-Key`)

Файл: `backend/app/api/admin_keys.py`  
Prefix: `/admin/keys`  
Auth: `Depends(verify_admin_key)` — сравнение с `ADMIN_API_KEY` из env (обычное `!=`, не constant-time).

| Method | Path | Body / Query | Ответ |
|--------|------|--------------|--------|
| `POST` | `/api/v1/admin/keys` | нет | `{ "key", "status" }` |
| `GET` | `/api/v1/admin/keys` | `?status=` optional | список `{id, key, status, device_id}` |
| `GET` | `/api/v1/admin/keys/{key}` | path = plaintext key | объект или `{status: not_found}` |
| `PATCH` | `/api/v1/admin/keys/revoke` | `{ "key": "..." }` | `{ "status": "..." }` |
| `PATCH` | `/api/v1/admin/keys/restore` | `{ "key": "..." }` | `{ "status": "..." }` |

Revoke statuses: `not_found` | `already_revoked` | `revoked`  
Restore statuses: `not_found` | `not_revoked` | `restored_to_activated` | `restored_to_created`

**Важно:** admin list/get возвращают **plaintext ключи** из БД. Это осознанно на текущем этапе (см. `ACCESS_KEY_HASHING_DEFERRED.md`); хеширование — позже.

### 3.3. Планируемые, но ещё не сделанные endpoints

```text
GET /api/v1/health
```

Отдельные `/activation`, `/devices/*`, block/unblock device **не входят в текущий MVP**.

---

## 4. ТЕКУЩИЕ МОДЕЛИ БД

### 4.1. `AccessKey` — таблица `access_keys`

Файл: `backend/app/models/access_key.py`

| Поле | Тип | Примечание |
|------|-----|------------|
| `id` | int PK | автоинкремент |
| `key` | String(64), unique | **plaintext**, не hash |
| `status` | String(20) | default `"created"`; значения: `created` / `activated` / `revoked` |
| `device_id` | String, nullable | **1 ключ ↔ 1 устройство** (зафиксировано) |
| `vpn_public_key` | String(255), unique, nullable | публичный VPN-ключ устройства |
| `vpn_ip` | String(45), unique, nullable | адрес в туннеле, напр. `10.8.0.x` |

Модель `VPNClient` / таблица `vpn_clients` **удалены** (миграция `a3f2c8d91e04`). VPN-поля лежат в `access_keys`.

### 4.2. Enum статусов (код)

Файл: `backend/app/models/enums.py`

```text
created
activated
revoked
```

Это **официальные** статусы MVP. Значения `active` / `blocked` / `expired` не использовать.

### 4.3. Что сознательно отложено

- отдельная сущность `Device` + `max_devices`
- `VpnServer`, `AdminAuditEvent`
- `key_hash` вместо plaintext (см. `ACCESS_KEY_HASHING_DEFERRED.md`)
- UUID вместо int id

---

## 5. ТЕКУЩИЕ СЕРВИСЫ И ЛОГИКА

### 5.1. `access_key_service.py`

- `generate_access_key()` → `BRATAN-{16 hex uppercase}` через `secrets.token_hex(8)`  
  (это текущий формат MVP; `BRTN-XXXX-...` не требуется)
- `create_access_key` — создаёт со статусом `created`
- `validate_access_key` — см. выше
- `revoke_access_key` / `restore_access_key` — смена статуса + (при revoke) remove peer через агент
- `get_access_keys` / `get_access_key`

### 5.2. `activation_service.py`

- Привязывает `device_id`, ставит `activated`
- Не трогает VPN

### 5.3. `vpn_service.py` (НЕ подключён к роутерам)

Функции:

- `allocate_ip(session)` — смотрит занятые `AccessKey.vpn_ip`, сеть `10.8.0.0/24`, пропускает `10.8.0.1`
- `assign_vpn_to_access_key(session, access_key, public_key, vpn_ip)` — пишет `vpn_public_key` и `vpn_ip` в строку ключа

Серверная генерация private key **удалена**. Public key должен приходить с клиента.

---

## 6. КОНФИГ, БД, DOCKER, МИГРАЦИИ

### 6.1. Env (`backend/app/core/config.py` + `.env.example`)

| Переменная | Обязательна | Назначение |
|------------|-------------|------------|
| `DATABASE_URL` | да | `postgresql+asyncpg://...` |
| `ADMIN_API_KEY` | да | значение для заголовка `X-Admin-Key` |
| `APP_NAME` | нет | default `BratanVPN API` |
| `APP_VERSION` | нет | default `0.1.0` |
| `DEBUG` | нет | default `false` (включает SQL echo) |

### 6.2. Docker Compose (корень)

Сервис только `postgres:16`:

- container: `bratanvpn-postgres`
- DB/user/password: `bratanvpn` / `bratanvpn` / `bratanvpn_password`
- порт хоста: **5433** → 5432
- volume: `postgres_data`

Нет сервисов: backend, caddy.

Пример локального URL для backend:

```text
postgresql+asyncpg://bratanvpn:bratanvpn_password@127.0.0.1:5433/bratanvpn
```

### 6.3. Alembic

- URL в `backend/alembic.ini` **захардкожен** (не читает `.env`):
  `postgresql+asyncpg://bratanvpn:bratanvpn_password@127.0.0.1:5433/bratanvpn`
- `env.py` — async migrations, импортирует `AccessKey`

Миграции:

| Revision | Что делает |
|----------|------------|
| `7b25f5a14fc7` | `ADD COLUMN device_id` к уже существующей `access_keys` (**не создаёт** таблицу access_keys) |
| `17a448b79be1` | создаёт `vpn_clients` (историческая; позже снята) |
| `a3f2c8d91e04` | поля `vpn_public_key`/`vpn_ip` в `access_keys`, drop `vpn_clients` |

Следствие: таблица `access_keys` исторически создавалась через `init_db` (`Base.metadata.create_all`), а не через первую миграцию.

### 6.4. Как поднять локально (текущий способ)

```bash
# из корня репо
docker compose up -d

# backend
cd backend
python -m venv .venv
# Windows:
.venv\Scripts\activate
pip install -e ".[dev]"
# создать .env из .env.example с правильным DATABASE_URL и ADMIN_API_KEY

# создать таблицы (один из путей):
python -m app.db.init_db
# и/или
alembic upgrade head

# запуск API
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

---

## 7. ЦЕЛЕВАЯ СПЕЦИФИКАЦИЯ (MVP) — куда идём

Полный текст правил: `.cursor/rules/bratanvpn.mdc`. Кратко ниже.

### 7.1. Целевой стек

| Слой | Технология |
|------|------------|
| Клиенты | Windows + Android, общий UI на Flutter |
| Android VPN | Kotlin + Android VpnService |
| Windows VPN | нативный сервис / отдельный процесс |
| Протокол | AmneziaWG 2.0 |
| Backend | Python 3.13 + FastAPI |
| DB | PostgreSQL + SQLAlchemy 2 + Alembic |
| Валидация | Pydantic |
| Compose | backend + postgres + caddy |
| Reverse proxy | Caddy (HTTPS/TLS) |
| Сервер | один Ubuntu VPS |
| Тесты backend | pytest |
| State management Flutter | Riverpod (один подход) |

**Не использовать в v1:** Ansible, Kubernetes, Redis, Kafka, Grafana/Prometheus на VPS, микросервисы, реальные оплаты, iOS/macOS/Linux-клиент, несколько локаций, рефералка, рекламные SDK, свой крипто/VPN-протокол.

### 7.2. Целевая структура монорепо

```text
bratanvpn/
├── apps/client/          # Flutter
├── backend/app/...
├── server/               # scripts, amneziawg, caddy, monitoring
├── infrastructure/       # docker-compose, .env.example
├── docs/
└── .cursor/rules/
```

### 7.3. Сущности MVP (зафиксировано)

**AccessKey:** id, key (plaintext пока), status (`created|activated|revoked`), device_id, vpn_public_key, vpn_ip  

Отдельный **Device** / `max_devices` — **не** в текущем MVP.  
**VpnServer** / **AdminAuditEvent** — опционально позже.

Формат ключа сейчас: `BRATAN-{16 hex}`. Хеширование — позже (`ACCESS_KEY_HASHING_DEFERRED.md`).

### 7.4. User flow активации

1. Пользователь вводит access key в приложении  
2. Приложение локально создаёт VPN keypair  
3. Private key остаётся только на устройстве  
4. На backend уходят: access key + device_id + public VPN key  
5. Backend активирует ключ (1 device), добавляет peer в AmneziaWG через агент  
6. Приложение получает VPN config  
7. Config сохраняется в secure storage  

### 7.5. Формат VPN config (ответ backend)

```json
{
  "schema_version": 1,
  "server": {
    "id": "uuid",
    "name": "Основной",
    "host": "vpn.example.com",
    "port": 12345
  },
  "protocol": {
    "type": "amneziawg",
    "config": {}
  }
}
```

Внутренне предусмотреть `VpnProtocol { amneziaWg, tlsFallback }`, но `tlsFallback` в v1 **не реализовывать** и не показывать в UI.

### 7.6. Отзыв доступа

При revoke ключа:

1. сменить статус на `revoked`  
2. удалить public key из AmneziaWG  
3. очистить vpn_ip / vpn_public_key / device_id в БД  
4. запретить выдачу config  
5. клиент при validate: остановить VPN, очистить конфиг, показать «Доступ заблокирован», не крутить reconnect  

Проверка статуса: при старте, при connect, периодически (не каждую секунду).

### 7.7. AmneziaWG агент (целевой)

Backend **не** должен от root править конфиги и выполнять произвольный shell.

Ограниченный агент/скрипт умеет только:

- add public key  
- remove public key  
- check public key exists  
- apply config  
- return interface status  

Все значения строго валидировать (формат public key и т.д.).

### 7.8. Flutter UI (целевой)

Минимализм: чёрный / белый / серый. Без зелёного как основного. Красный — только ошибки/блок.  
Главный экран: бренд, статус, большая кнопка, сервер, задержка, статус доступа.  
Connected = инверсия цветов (чёрный фон).  
Состояния: disconnected, connecting, connected, disconnecting, error, access_blocked, server_unavailable.

Secure storage: device token, private VPN key, device id, last config, activation status.  
Не класть секреты в SharedPreferences / логи.

### 7.9. Health-check (целевой)

`GET /api/v1/health` проверяет: API, PostgreSQL, disk free, VPN interface, apply config, внешний интернет.  
Уведомления админу (Telegram/email) при падениях.

### 7.10. Критерии готовности MVP (чек-лист)

1. Админ создаёт ключ  
2. Пользователь вводит ключ в Windows/Android  
3. Устройство создаёт локальную VPN-пару  
4. Backend регистрирует public key  
5. Сервер добавляет peer в AmneziaWG  
6. Приложение получает конфиг  
7. Подключение одной кнопкой  
8. Интернет через VPS  
9. DNS через VPN  
10. UI показывает статус  
11. Админ блокирует ключ  
12. Public key удаляется с сервера  
13. Пользователь теряет доступ  
14. Private key ни разу не покидал устройство  
15. Нет логов истории сайтов/DNS  
16. Backend+DB через Compose  
17. Health-check работает  
18. Дизайн ч/б минималистичный  

---

## 8. РАЗРЫВ: что ещё нужно (карта долгов)

| Область | Сейчас | Нужно для MVP |
|---------|--------|----------------|
| Access key storage | plaintext | позже hash (отложено осознанно) |
| Statuses | created/activated/revoked | **уже ок — не менять** |
| Devices | `device_id` на AccessKey | **уже ок (1=1) — не плодить Device** |
| VPN keys на клиенте | X25519 + secure vault | ок; дальше — config в vault |
| VPN config API | backend есть | вызвать из Flutter + сохранить |
| Validate / access check | backend есть | периодически из клиента |
| Health | нет | `GET /api/v1/health` |
| Admin API | `/admin/keys` revoke/restore | ок для MVP; CLI — опционально |
| AmneziaWG sync | агент + SSH | prod local mode / hardening |
| Flutter UI | экран + активация | нативный туннель |
| Compose | postgres (+ local uvicorn) | postgres + backend + caddy — см. `docs/DEPLOYMENT_DOCKER.md` |
| Tests | Flutter частично | pytest критического пути + health — см. `docs/BACKEND_TESTING.md` |
| Rate limit activation | нет | желательно |

---

## 9. ЖЁСТКИЕ ЗАПРЕТЫ (нельзя нарушать)

1. Не пропускать VPN-трафик через FastAPI.  
2. Не отправлять / хранить / логировать private VPN key.  
3. Не класть `ADMIN_API_KEY` во Flutter.  
4. Не открывать admin API без авторизации.  
5. Не отключать TLS «ради удобства» на проде.  
6. Не давать backend произвольный shell на хосте.  
7. Не изобретать свою криптографию / VPN-протокол.  
8. Не добавлять оплаты, iOS, multi-location, Redis, K8s без запроса.  
9. Не оставлять `TODO: implement later` в критических путях.  
10. Не коммитить `.env` с секретами.  
11. Не возвращать stack trace пользователю.  
12. Не писать SQL строковой конкатенацией.  
13. **Не рефакторить** статусы/API/`Device` «под старую спеку» без явного запроса пользователя.

Коды ошибок (MVP):  
`INVALID_ACCESS_KEY`, `ACCESS_KEY_REVOKED`, `DEVICE_MISMATCH`, `SERVER_UNAVAILABLE`, `VPN_START_FAILED`, `VPN_CONFIG_INVALID`, `API_UNAVAILABLE`, `NETWORK_UNAVAILABLE`.

---

## 10. РЕКОМЕНДУЕМЫЙ ПОРЯДОК ДОРАБОТКИ (для следующих задач)

Если AI просят «продолжить проект» без уточнения — логичный порядок:

1. Flutter: `GET /vpn/config` + сохранить в vault  
2. Flutter: периодический `POST /validate` при revoke  
3. Нативный VPN-туннель (сначала одна платформа)  
4. Health-check  
5. pytest критического пути  
6. Dockerize backend + Caddy  
7. (Позже, отдельным решением) hash ключей / multi-device / VpnServer  

При любом шаге: не ломать локальный dev-путь (Postgres на 5433), обновлять этот файл или docs при крупных сдвигах.

---

## 11. ШПАРГАЛКА ПО ФАЙЛАМ (куда смотреть)

| Задача | Файлы |
|--------|-------|
| Точки входа API | `backend/app/main.py`, `backend/app/api/*.py` |
| Бизнес-логика ключей | `backend/app/services/access_key_service.py`, `activation_service.py` |
| VPN-заготовки | `backend/app/services/vpn_service.py`, поля в `models/access_key.py` |
| Настройки | `backend/app/core/config.py`, `backend/.env.example` |
| Admin auth | `backend/app/core/security.py` |
| ORM base/session | `backend/app/db/*` |
| Миграции | `backend/alembic/versions/*` |
| Целевые правила | `.cursor/rules/bratanvpn.mdc` |
| Compose | `docker-compose.yml` (корень) |

---

## 12. КРАТКИЙ ВЕРДИКТ ОДНИМ АБЗАЦЕМ

BratanVPN — монорепозиторий: FastAPI (activate / validate / vpn/config / admin keys revoke-restore) + PostgreSQL, AmneziaWG-агент на VPS, Flutter-клиент с UI/активацией/X25519/secure vault. Схема MVP зафиксирована: статусы `created|activated|revoked`, **1 ключ = 1 устройство**, API как сейчас. Главный пробел — нативный VPN-туннель в клиенте; также health, compose+caddy, pytest. Хеш access key отложен осознанно. Подробности: `.cursor/rules/bratanvpn.mdc`.

---

## 13. ПРИМЕРЫ ЗАПРОСОВ К ТЕКУЩЕМУ API

```bash
# создать ключ (admin)
curl -X POST http://127.0.0.1:8000/api/v1/admin/keys \
  -H "X-Admin-Key: change-me"

# активировать
curl -X POST http://127.0.0.1:8000/api/v1/activate \
  -H "Content-Type: application/json" \
  -d "{\"access_key\":\"BRATAN-...\",\"device_id\":\"device-1\"}"

# проверить
curl -X POST http://127.0.0.1:8000/api/v1/validate \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"BRATAN-...\",\"device_id\":\"device-1\"}"

# revoke
curl -X PATCH http://127.0.0.1:8000/api/v1/admin/keys/revoke \
  -H "X-Admin-Key: change-me" \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"BRATAN-...\"}"
```

---

*Конец документа. При существенных изменениях кода — обнови разделы 2–6 и 8.*
