#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/etc/siem-pqc-gateway"
BIN_PATH="/usr/local/bin/siem-pqc-gateway"
LOGSTASH_PIPELINE_DIR="${LOGSTASH_PIPELINE_DIR:-}"

echo "[0/5] Checking requirements"
command -v go >/dev/null 2>&1 || { echo "[ERROR] Go is required to build pqc-gateway.go"; exit 1; }
if ! go version | grep -Eq 'go1\.(2[4-9]|[3-9][0-9])'; then
  echo "[WARN] Go version should support crypto/tls X25519MLKEM768. Recommended Go >= 1.24."
  go version
fi

echo "[1/5] Installing gateway config"
sudo mkdir -p "${INSTALL_DIR}/certs"
sudo cp "${SCRIPT_DIR}/gateway.yaml" "${INSTALL_DIR}/gateway.yaml"

if [[ ! -f "${INSTALL_DIR}/certs/server.crt" || ! -f "${INSTALL_DIR}/certs/server.key" ]]; then
  echo "[2/5] Creating lab self-signed TLS certificate"
  sudo openssl req -x509 -newkey rsa:3072 -nodes \
    -keyout "${INSTALL_DIR}/certs/server.key" \
    -out "${INSTALL_DIR}/certs/server.crt" \
    -days 365 \
    -subj "/CN=siem-pqc-gateway" \
    -addext "subjectAltName=IP:192.168.22.171,DNS:siem-pqc-gateway,DNS:localhost"
else
  echo "[2/5] Existing gateway certificate found"
fi

echo "[3/5] Building and installing gateway binary"
go build -o /tmp/siem-pqc-gateway "${SCRIPT_DIR}/pqc-gateway.go"
sudo install -m 0755 /tmp/siem-pqc-gateway "${BIN_PATH}"

echo "[4/5] Installing systemd service"
sudo cp "${SCRIPT_DIR}/siem-pqc-gateway.service" /etc/systemd/system/siem-pqc-gateway.service
sudo systemctl daemon-reload
sudo systemctl enable --now siem-pqc-gateway

echo "[5/5] Logstash pipeline reminder"
if [[ -n "${LOGSTASH_PIPELINE_DIR}" ]]; then
  sudo mkdir -p "${LOGSTASH_PIPELINE_DIR}"
  sudo cp "${SCRIPT_DIR}/logstash/pipeline/ncs-pqc.conf" "${LOGSTASH_PIPELINE_DIR}/ncs-pqc.conf"
  echo "[OK] Copied Logstash pipeline to ${LOGSTASH_PIPELINE_DIR}/ncs-pqc.conf"
  echo "[INFO] Restart Logstash after copying the pipeline."
else
  echo "[INFO] Set LOGSTASH_PIPELINE_DIR=/path/to/logstash/pipeline to auto-copy ncs-pqc.conf."
  echo "[INFO] Pipeline source: ${SCRIPT_DIR}/logstash/pipeline/ncs-pqc.conf"
fi

echo "[OK] NCS PQC receiver setup complete"
