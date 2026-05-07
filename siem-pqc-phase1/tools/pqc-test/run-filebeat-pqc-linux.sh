#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILEBEAT_BIN="${FILEBEAT_BIN:-${ROOT_DIR}/build/filebeat-pqc-linux-amd64}"
FILEBEAT_CONFIG="${FILEBEAT_CONFIG:-${ROOT_DIR}/tools/pqc-test/example-filebeat-pqc.yml}"

export LOGSTASH_TLS_CURVE_TYPES="${LOGSTASH_TLS_CURVE_TYPES:-X25519MLKEM768}"
export LOGSTASH_TLS_MIN_VERSION="${LOGSTASH_TLS_MIN_VERSION:-1.3}"
export LOGSTASH_TLS_STRICT_PQC="${LOGSTASH_TLS_STRICT_PQC:-true}"

echo "Using filebeat binary: ${FILEBEAT_BIN}"
echo "Using config: ${FILEBEAT_CONFIG}"
echo "LOGSTASH_TLS_CURVE_TYPES=${LOGSTASH_TLS_CURVE_TYPES}"
echo "LOGSTASH_TLS_MIN_VERSION=${LOGSTASH_TLS_MIN_VERSION}"
echo "LOGSTASH_TLS_STRICT_PQC=${LOGSTASH_TLS_STRICT_PQC}"

exec "${FILEBEAT_BIN}" -c "${FILEBEAT_CONFIG}" -e -d "logstash,tls,pqc"

