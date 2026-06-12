#!/usr/bin/env bash
set -euo pipefail

INDEX_PATTERN="${INDEX_PATTERN:-phase1-pqc-filebeat-*}"
ELASTIC_USER="${ELASTIC_USER:-elastic}"

echo "[1/4] Listening ports"
ss -lntp | grep -E ':5443|:5044' || true

echo
echo "[2/4] Gateway service"
systemctl --no-pager --full status siem-pqc-gateway || true

echo
echo "[3/4] Recent gateway logs"
journalctl -u siem-pqc-gateway -n 80 --no-pager || true

echo
echo "[4/4] Elasticsearch index check"
if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
  curl -k -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" "https://localhost:9200/_cat/indices/${INDEX_PATTERN}?v" || true
else
  echo "[INFO] Set ELASTIC_PASSWORD to check ${INDEX_PATTERN} indices."
  echo "       Example: ELASTIC_PASSWORD='<password>' ./check-pqc-gateway.sh"
fi
