#!/bin/sh
# Wait for Postgres, apply migrations, start API.
set -eu

echo "Running database migrations..."
alembic upgrade head

echo "Starting uvicorn..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
