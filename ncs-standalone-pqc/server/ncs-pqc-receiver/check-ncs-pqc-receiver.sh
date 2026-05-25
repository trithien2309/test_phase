#!/usr/bin/env bash
set -euo pipefail

echo "[1/4] Listening ports"
ss -lntp | grep -E ':5443|:5044' || true

echo
echo "[2/4] Gateway service"
systemctl --no-pager --full status siem-pqc-gateway || true

echo
echo "[3/4] Recent gateway logs"
journalctl -u siem-pqc-gateway -n 50 --no-pager || true

echo
echo "[4/4] Elasticsearch index check"
if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
  curl -k -u "elastic:${ELASTIC_PASSWORD}" "https://localhost:9200/_cat/indices/ncs-windows-pqc-*?v" || true
else
  echo "[INFO] Set ELASTIC_PASSWORD to check ncs-windows-pqc-* indices."
  echo "       Example: ELASTIC_PASSWORD='<password>' ./check-ncs-pqc-receiver.sh"
fi
