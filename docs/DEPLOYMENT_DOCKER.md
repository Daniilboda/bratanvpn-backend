# Docker Compose: backend + PostgreSQL + Caddy

Как запускать BratanVPN API в контейнерах.

## Что поднимается

| Сервис | Роль |
|--------|------|
| `postgres` | База данных (внутри Docker-сети, снаружи по умолчанию **не** открыта) |
| `backend` | FastAPI (миграции Alembic при старте, пользователь **не root**) |
| `caddy` | HTTPS/HTTP reverse proxy → `backend:8000` |

AmneziaWG остаётся **на хосте** Ubuntu (не в контейнере).

## Файлы

```text
docker-compose.yml          — основной стек
docker-compose.dev.yml      — открыть Postgres на localhost:5433 (локальная разработка)
.env.example                — пример переменных для Compose (копировать в .env)
backend/Dockerfile
server/caddy/Caddyfile
```

## Подготовка

1. Скопируй пример env в корень репозитория:

```bash
cp .env.example .env
```

Без `.env` полный стек (backend) не получит `ADMIN_API_KEY` и другие секреты — файл обязателен для `docker compose up`.  
`env_file` в compose помечен как необязательный только чтобы `docker compose config` / подъём одного Postgres не падали, если `.env` ещё нет.
2. Заполни секреты: `POSTGRES_PASSWORD`, `ADMIN_API_KEY`, VPN-параметры, SSH к агенту.

3. Для продакшена на VPS укажи домен:

```env
SITE_ADDRESS=api.твой-домен.com
```

Caddy сам получит TLS-сертификат (нужны открытые порты 80/443 и DNS на VPS).

Для быстрой локальной проверки без домена оставь:

```env
SITE_ADDRESS=:80
```

(только HTTP, без настоящего HTTPS).

## Повторный деплой с Windows

Скрипт (секреты читает из `backend/.env`, в лог не печатает пароли):

```powershell
$env:PYTHONIOENCODING='utf-8'
.\backend\.venv\Scripts\python.exe .\server\scripts\deploy_vps.py
```

Кладёт код в `/opt/bratanvpn`, ставит Docker при необходимости, делает `docker compose up -d --build`.

Сейчас на VPS API доступен по HTTPS:

```text
https://api.bratanvpn.com/api/v1/health
```

(Let’s Encrypt через Caddy; DNS A `api` → IP VPS, Proxy = DNS only)

Логи:

```bash
docker compose logs -f backend
```

## Только Postgres для локального uvicorn (как раньше)

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d postgres
```

База будет на `127.0.0.1:5433`. Backend на хосте:

```bash
cd backend
uvicorn app.main:app --reload
```

`DATABASE_URL` в `backend/.env` — на `127.0.0.1:5433`.

## VPN-агент и Docker

Агент AmneziaWG требует root на хосте. Из контейнера backend удобнее звонить ему по **SSH на хост**:

```env
VPN_AGENT_MODE=ssh
VPN_AGENT_SSH_HOST=host.docker.internal
VPN_AGENT_SSH_USER=root
VPN_AGENT_SSH_PASSWORD=...
VPN_AGENT_PATH=/usr/local/sbin/bratanvpn-awg-agent
```

В `docker-compose.yml` уже есть `extra_hosts: host.docker.internal:host-gateway`.

Если backend запущен **на самом хосте** (не в Docker):

```env
VPN_AGENT_MODE=local
VPN_AGENT_PATH=/usr/local/sbin/bratanvpn-awg-agent
```

(`local` = прямой запуск скрипта агента через subprocess, без SSH; произвольный shell не используется.)

## Безопасность (кратко)

* Postgres в основном compose **без** `ports:` — с интернета не торчит.
* Наружу у Caddy: 80 и 443.
* Backend в контейнере от пользователя `app` (uid 10001).
* Логи Docker ограничены (`max-size: 10m`).
* Файл `.env` с секретами **не** коммитить.

## Остановка

```bash
docker compose down
```

Данные Postgres сохраняются в volume `postgres_data`.
