#!/usr/bin/env bash
set -euo pipefail

LOG_ROOT="/opt/Elastic/Agent/data"
ENV_FILE="/etc/ncs-elastic-agent/pqc.env"
FAILED=0

pass() { printf '  [PASS] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; FAILED=1; }

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this checker with sudo/root." >&2
  exit 2
fi

echo "[1/5] Services"
systemctl is-active --quiet elastic-agent && pass "elastic-agent is active" || fail "elastic-agent is not active"
systemctl is-active --quiet auditd && pass "auditd is active" || fail "auditd is not active"

echo "[2/5] Installed component"
INSTALLED_HOME="$(find "$LOG_ROOT" -maxdepth 1 -mindepth 1 -type d -name 'elastic-agent-*' 2>/dev/null | sort | tail -n 1 || true)"
if [[ -n "$INSTALLED_HOME" && -x "${INSTALLED_HOME}/components/testbeat" && -f "${INSTALLED_HOME}/components/testbeat.spec.yml" ]]; then
  pass "testbeat component files exist in ${INSTALLED_HOME}/components"
else
  fail "testbeat component files are missing"
fi

echo "[3/5] PQC process and environment"
pgrep -af 'filebeat-pqc-linux-amd64|testbeat' >/dev/null && pass "Filebeat PQC/testbeat process is running" || fail "Filebeat PQC/testbeat process is not running"
for expected in \
  'LOGSTASH_TLS_CURVE_TYPES=X25519MLKEM768' \
  'LOGSTASH_TLS_MIN_VERSION=1.3' \
  'LOGSTASH_TLS_STRICT_PQC=true'; do
  grep -Fxq "$expected" "$ENV_FILE" 2>/dev/null && pass "$expected" || fail "Missing $expected"
done
grep -Eq '^PQC_FILEBEAT_BIN=.+filebeat-pqc-linux-amd64$' "$ENV_FILE" 2>/dev/null && pass "PQC_FILEBEAT_BIN is configured" || fail "PQC_FILEBEAT_BIN is missing"

echo "[4/5] Agent errors"
if grep -RhiE 'input not supported|unknown flavor' "$LOG_ROOT" >/dev/null 2>&1; then
  fail "Agent logs contain input/flavor errors"
  grep -RhiE 'input not supported|unknown flavor' "$LOG_ROOT" 2>/dev/null | tail -n 20
else
  pass "No input/flavor errors found"
fi

echo "[5/5] PQC/TLS evidence"
for marker in 'using_custom_filebeat' 'pqc_env_forwarded' 'pqc_mode' 'TLS handshake completed' 'X25519MLKEM768' 'strict_pqc'; do
  if grep -RhiF "$marker" "$LOG_ROOT" >/dev/null 2>&1; then
    pass "Found marker: $marker"
  else
    fail "Missing marker: $marker"
  fi
done

echo
echo "Server verification:"
echo "  tail -f /home/ncs/pqc-phase1/pqc-gateway.log"
echo "  Confirm TLS 1.3, forwarding to 127.0.0.1:5044, and client->logstash bytes > 0."

exit "$FAILED"
