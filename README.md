# BratanVPN Backend

Backend для VPN-сервиса BratanVPN.

Проект управляет ключами доступа, активацией устройств и в дальнейшем будет автоматически создавать конфигурации AmneziaWG.

## Стек

* Python
* FastAPI
* PostgreSQL
* SQLAlchemy Async
* Alembic
* Docker Compose
* AmneziaWG

## Реализовано

* создание ключей доступа;
* получение списка ключей;
* фильтрация ключей по статусу;
* активация ключа на устройстве;
* проверка ключа клиентом;
* отзыв ключа;
* восстановление ключа;
* защита административного API через `X-Admin-Key`.

## Статусы ключей

* `created` — ключ создан, но ещё не активирован;
* `activated` — ключ привязан к устройству;
* `revoked` — ключ отозван администратором.

## Структура проекта

```text
app/
├── api/
├── core/
├── db/
├── models/
├── services/
└── main.py

alembic/
tests/
```

## Настройка окружения

Создай файл `.env` на основе `.env.example`.

Пример:

```env
APP_NAME=BratanVPN
APP_VERSION=0.1.0
DEBUG=False
DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/bratanvpn
ADMIN_API_KEY=replace_with_secret_key
```

Не добавляй файл `.env` в Git.

## Запуск PostgreSQL

```bash
docker compose up -d
```

## Применение миграций

```bash
alembic upgrade head
```

## Запуск backend

```bash
uvicorn app.main:app --reload
```

После запуска документация Swagger будет доступна по адресу:

```text
http://127.0.0.1:8000/docs
```

## API

Клиентские маршруты:

```text
POST /api/v1/activate
POST /api/v1/validate
```

Административные маршруты:

```text
POST  /api/v1/admin/keys/
GET   /api/v1/admin/keys/
GET   /api/v1/admin/keys/{key}
PATCH /api/v1/admin/keys/revoke
PATCH /api/v1/admin/keys/restore
```

Для административных запросов требуется заголовок:

```text
X-Admin-Key
```

## Следующий этап

Интеграция backend с AmneziaWG:

* создание VPN-клиента;
* добавление peer на сервер;
* генерация клиентской конфигурации;
* удаление и блокировка VPN-доступа.
