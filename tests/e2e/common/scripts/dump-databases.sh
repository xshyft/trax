#!/bin/bash
# Dump PostgreSQL and Redis databases
# Usage: dump-databases.sh <output-dir> <postgres-host> <postgres-port> <db-name> <user> <password>

set -e

if [ $# -ne 6 ]; then
    echo "Usage: $0 <output-dir> <postgres-host> <postgres-port> <db-name> <user> <password>"
    exit 1
fi

OUTPUT_DIR="$1"
POSTGRES_HOST="$2"
POSTGRES_PORT="$3"
DB_NAME="$4"
DB_USER="$5"
DB_PASSWORD="$6"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Dumping PostgreSQL database..."

# Set password for pg_dump
export PGPASSWORD="$DB_PASSWORD"

# Full dump
echo "  - Full dump: postgres_dump.sql"
pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$DB_USER" -d "$DB_NAME" \
    --no-password -F p > "$OUTPUT_DIR/postgres_dump.sql"

# Schema-only dump
echo "  - Schema dump: postgres_schema.sql"
pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$DB_USER" -d "$DB_NAME" \
    --no-password -F p --schema-only > "$OUTPUT_DIR/postgres_schema.sql"

echo "PostgreSQL dumps completed"

# Redis dump (best effort)
echo "Triggering Redis dump..."
redis-cli -h redis -p 6379 SAVE || echo "  Warning: Redis SAVE failed"

echo "Database dumps completed in: $OUTPUT_DIR"
