#!/bin/bash
set -e

echo "Waiting for PostgreSQL..."
until pg_isready -h db -U "${POSTGRES_USER:-revos}" -q; do
  sleep 1
done

echo "Running migrations..."
cd /app && alembic upgrade head

echo "Database initialized."
