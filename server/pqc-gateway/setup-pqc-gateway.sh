#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

INSTALL_DIR="${INSTALL_DIR:-/etc/siem-pqc-gateway}"
BIN_PATH="${BIN_PATH:-/usr/local/bin/siem-pqc-gateway}"
SERVICE_PATH="${SERVICE_PATH:-/etc/systemd/system/siem-pqc-gateway.service}"
GATEWAY_IP="${GATEWAY_IP:-192.168.22.171}"
LOGSTASH_PIPELINE_DIR="${LOGSTASH_PIPELINE_DIR:-}"

echo "[0/6] Checking requirements"
command -v go >/dev/null 2>&1 || { echo "[ERROR] Go is required to build pqc-gateway.go"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "[ERROR] openssl is required to create the lab TLS certificate"; exit 1; }
if ! go version | grep -Eq 'go1\.(2[4-9]|[3-9][0-9])'; then
  echo "[WARN] Go version should support crypto/tls X25519MLKEM768. Recommended Go >= 1.24."
  go version
fi

echo "[1/6] Installing gateway config"
sudo mkdir -p "${INSTALL_DIR}/certs"
sudo cp "${SCRIPT_DIR}/gateway.yaml" "${INSTALL_DIR}/gateway.yaml"

if [[ ! -f "${INSTALL_DIR}/certs/server.crt" || ! -f "${INSTALL_DIR}/certs/server.key" ]]; then
  echo "[2/6] Creating lab self-signed TLS certificate"
  echo "[INFO] Certificate SAN IP: ${GATEWAY_IP}"
  sudo openssl req -x509 -newkey rsa:3072 -nodes \
    -keyout "${INSTALL_DIR}/certs/server.key" \
    -out "${INSTALL_DIR}/certs/server.crt" \
    -days 365 \
    -subj "/CN=siem-pqc-gateway" \
    -addext "subjectAltName=IP:${GATEWAY_IP},DNS:siem-pqc-gateway,DNS:localhost"
else
  echo "[2/6] Existing gateway certificate found"
fi

echo "[3/6] Building and installing gateway binary"
cd "${REPO_ROOT}"
go build -o /tmp/siem-pqc-gateway ./server/pqc-gateway
sudo install -m 0755 /tmp/siem-pqc-gateway "${BIN_PATH}"

echo "[4/6] Installing systemd service"
sudo cp "${SCRIPT_DIR}/siem-pqc-gateway.service" "${SERVICE_PATH}"
sudo systemctl daemon-reload
sudo systemctl enable --now siem-pqc-gateway

echo "[5/6] Logstash pipeline"
if [[ -n "${LOGSTASH_PIPELINE_DIR}" ]]; then
  sudo mkdir -p "${LOGSTASH_PIPELINE_DIR}"
  sudo cp "${REPO_ROOT}/server/logstash/pipeline/phase1-pqc-filebeat.conf" "${LOGSTASH_PIPELINE_DIR}/phase1-pqc-filebeat.conf"
  echo "[OK] Copied Logstash pipeline to ${LOGSTASH_PIPELINE_DIR}/phase1-pqc-filebeat.conf"
  echo "[INFO] Restart Logstash after copying the pipeline."
else
  echo "[INFO] Set LOGSTASH_PIPELINE_DIR=/path/to/logstash/pipeline to auto-copy the pipeline."
  echo "[INFO] Pipeline source: ${REPO_ROOT}/server/logstash/pipeline/phase1-pqc-filebeat.conf"
fi

echo "[6/6] Current listener check"
ss -lntp | grep -E ':5443|:5044' || true

echo "[OK] NCS PQC Gateway setup complete"
