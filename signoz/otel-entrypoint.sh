#!/bin/bash
set -e

echo "=== OTel Collector Entrypoint Starting ==="

CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-clickhouse}"

# Wait for ClickHouse to be ready (using bash /dev/tcp since wget/curl not available)
echo "Waiting for ClickHouse to be ready at ${CLICKHOUSE_HOST}:8123..."
MAX_WAIT=300
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  if (echo > /dev/tcp/${CLICKHOUSE_HOST}/8123) 2>/dev/null; then
    echo "ClickHouse is ready! (port 8123 open after ${WAITED}s)"
    break
  fi
  echo "ClickHouse at ${CLICKHOUSE_HOST} not ready, waiting 5s... (${WAITED}s/${MAX_WAIT}s)"
  sleep 5
  WAITED=$((WAITED + 5))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  echo "WARNING: Timed out waiting for ClickHouse after ${MAX_WAIT}s, proceeding anyway..."
fi

# Brief delay for ClickHouse to fully initialize after port opens
sleep 5

# Remove any manager config the base image may ship - the signoz-collector
# binary auto-discovers /etc/manager-config.yaml and OpAmp pushes a dynamic
# config with Docker-style hostnames that break Railway DNS resolution.
rm -f /etc/manager-config.yaml

echo "Starting OTel Collector (OpAmp disabled - static config only)..."
exec /signoz-otel-collector \
  --config=/etc/otel-collector-config.yaml \
  --copy-path=/var/tmp/collector-config.yaml \
  --feature-gates=-pkg.translator.prometheus.NormalizeName
