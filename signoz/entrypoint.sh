#!/bin/sh
set -e

echo "=== SigNoz Entrypoint Starting ==="

# Wait for ClickHouse to be ready
echo "Waiting for ClickHouse to be ready..."
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-clickhouse}"
until wget --spider -q "http://${CLICKHOUSE_HOST}:8123/ping" 2>/dev/null; do
  echo "ClickHouse at ${CLICKHOUSE_HOST} not ready, waiting 5s..."
  sleep 5
done
echo "ClickHouse is ready!"

# Drop existing databases for fresh start if enabled
if [ "${FRESH_START:-false}" = "true" ]; then
  echo "FRESH_START enabled - dropping existing databases..."
  wget -qO- "http://${CLICKHOUSE_HOST}:8123/?query=DROP%20DATABASE%20IF%20EXISTS%20signoz_traces" 2>/dev/null || true
  wget -qO- "http://${CLICKHOUSE_HOST}:8123/?query=DROP%20DATABASE%20IF%20EXISTS%20signoz_metrics" 2>/dev/null || true
  wget -qO- "http://${CLICKHOUSE_HOST}:8123/?query=DROP%20DATABASE%20IF%20EXISTS%20signoz_logs" 2>/dev/null || true
  echo "Databases dropped. Migrations will recreate them."
  sleep 5
fi

# Reset user database if requested (allows fresh registration)
if [ "${RESET_USERS:-false}" = "true" ]; then
  SQLITE_PATH="${SIGNOZ_SQLSTORE_SQLITE_PATH:-/var/lib/signoz/signoz.db}"
  echo "RESET_USERS enabled - removing user database at ${SQLITE_PATH}..."
  rm -f "${SQLITE_PATH}" "${SQLITE_PATH}-journal" "${SQLITE_PATH}-wal" "${SQLITE_PATH}-shm" 2>/dev/null || true
  echo "User database removed. First user to register will become admin."
fi

# Wait for schema migrations to complete by checking for required tables
echo "Waiting for schema migrations to complete..."
MAX_WAIT=300
WAITED=0
INTERVAL=10

# Check for the distributed_signoz_index_v3 table which is created by recent migrations
while [ $WAITED -lt $MAX_WAIT ]; do
  # Query ClickHouse to check if the traces table exists
  RESULT=$(wget -qO- "http://${CLICKHOUSE_HOST}:8123/?query=SELECT%20count()%20FROM%20system.tables%20WHERE%20database='signoz_traces'%20AND%20name='distributed_signoz_index_v3'" 2>/dev/null || echo "0")

  if [ "$RESULT" = "1" ]; then
    echo "Schema migrations appear complete (found distributed_signoz_index_v3 table)"
    break
  fi

  echo "Waiting for migrations... (${WAITED}s/${MAX_WAIT}s)"
  sleep $INTERVAL
  WAITED=$((WAITED + INTERVAL))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  echo "WARNING: Timed out waiting for migrations, proceeding anyway..."
fi

# Extra buffer for any final migration steps
echo "Waiting additional 10s for migration finalization..."
sleep 10

echo "Starting SigNoz server..."
exec ./signoz-community server --config=/root/config/prometheus.yml "$@"
