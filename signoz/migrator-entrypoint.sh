#!/bin/sh
set -e

echo "=== Schema Migrator Starting ==="

# Configuration from environment
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-clickhouse}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-9000}"
CLUSTER_NAME="${SIGNOZ_CLUSTER_NAME:-cluster}"

echo "ClickHouse Host: ${CLICKHOUSE_HOST}"
echo "ClickHouse Port: ${CLICKHOUSE_PORT}"
echo "Cluster Name: ${CLUSTER_NAME}"

# Wait for ClickHouse to be ready (TCP port 9000)
echo "Waiting for ClickHouse TCP port to be ready..."
until nc -z "${CLICKHOUSE_HOST}" "${CLICKHOUSE_PORT}" 2>/dev/null; do
  echo "ClickHouse at ${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT} not ready, waiting 5s..."
  sleep 5
done
echo "ClickHouse TCP port is ready!"

# Also check HTTP port for good measure
echo "Waiting for ClickHouse HTTP port to be ready..."
until wget --spider -q "http://${CLICKHOUSE_HOST}:8123/ping" 2>/dev/null; do
  echo "ClickHouse HTTP at ${CLICKHOUSE_HOST}:8123 not ready, waiting 5s..."
  sleep 5
done
echo "ClickHouse HTTP is ready!"

# Give ClickHouse a moment to fully initialize
sleep 5

# Build DSN
DSN="tcp://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}"

# Drop existing databases for fresh start (remove this block after first successful run)
if [ "${FRESH_START:-false}" = "true" ]; then
  echo "FRESH_START enabled - dropping existing databases..."
  wget -qO- "http://${CLICKHOUSE_HOST}:8123/?query=DROP%20DATABASE%20IF%20EXISTS%20signoz_traces%20ON%20CLUSTER%20${CLUSTER_NAME}" 2>/dev/null || true
  wget -qO- "http://${CLICKHOUSE_HOST}:8123/?query=DROP%20DATABASE%20IF%20EXISTS%20signoz_metrics%20ON%20CLUSTER%20${CLUSTER_NAME}" 2>/dev/null || true
  wget -qO- "http://${CLICKHOUSE_HOST}:8123/?query=DROP%20DATABASE%20IF%20EXISTS%20signoz_logs%20ON%20CLUSTER%20${CLUSTER_NAME}" 2>/dev/null || true
  echo "Databases dropped. Waiting for ClickHouse to settle..."
  sleep 5
fi

# Migration mode: sync (default) or async
MODE="${MIGRATION_MODE:-sync}"
echo "Running ${MODE} migrations..."

if [ "${MODE}" = "async" ]; then
  /signoz-schema-migrator async --dsn="${DSN}" --cluster-name="${CLUSTER_NAME}" --replication=false --skip-duration-seconds=120
else
  /signoz-schema-migrator sync --dsn="${DSN}" --cluster-name="${CLUSTER_NAME}" --replication=false
fi

echo "=== Schema Migrator (${MODE}) Completed Successfully ==="

# Keep container running briefly so Railway doesn't restart it
sleep 10
