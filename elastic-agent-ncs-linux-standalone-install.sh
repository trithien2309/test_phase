#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_BASE_URL="https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages"
BOOTSTRAP_BASE_URL="https://raw.githubusercontent.com/trithien2309/test_phase/demo"
ARTIFACT_PRIVATE_TOKEN=""
INSTALL_ROOT="/opt/ncs-elastic-agent-standalone"

ARGS=("$@")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-base-url)
      ARTIFACT_BASE_URL="${2:-}"
      shift 2
      ;;
    --artifact-base-url=*)
      ARTIFACT_BASE_URL="${1#*=}"
      shift
      ;;
    --bootstrap-base-url)
      BOOTSTRAP_BASE_URL="${2:-}"
      shift 2
      ;;
    --bootstrap-base-url=*)
      BOOTSTRAP_BASE_URL="${1#*=}"
      shift
      ;;
    --artifact-private-token)
      ARTIFACT_PRIVATE_TOKEN="${2:-}"
      shift 2
      ;;
    --artifact-private-token=*)
      ARTIFACT_PRIVATE_TOKEN="${1#*=}"
      shift
      ;;
    --install-root)
      INSTALL_ROOT="${2:-}"
      shift 2
      ;;
    --install-root=*)
      INSTALL_ROOT="${1#*=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPLEMENTATION="${SCRIPT_DIR}/client/linux/elastic-agent-ncs-linux-standalone-install.sh"

log_bootstrap() {
  printf '  [BOOTSTRAP] %s\n' "$1"
}

download_file() {
  local uri="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  log_bootstrap "Downloading ${uri}"
  if [[ -n "$ARTIFACT_PRIVATE_TOKEN" ]]; then
    curl -fL --retry 2 --retry-delay 2 -H "PRIVATE-TOKEN: ${ARTIFACT_PRIVATE_TOKEN}" -o "$destination" "$uri"
  else
    curl -fL --retry 2 --retry-delay 2 -o "$destination" "$uri"
  fi
}

ensure_bootstrap_payload() {
  local base_url="${1%/}"
  local bootstrap_root="$2"
  local required_files=(
    "client/linux/elastic-agent-ncs-linux-standalone-install.sh"
    "client/linux/packages/manifest.json"
    "client/linux/packages/SHA256SUMS.txt"
    "client/linux/resources/auditd/conf/ubuntu_audit.rules"
    "client/linux/resources/auditd/conf/centos_audit.rules"
    "client/linux/resources/auditd/conf/centos6_audit.rules"
    "client/linux/resources/auditd/conf/rhel6_audit.rules"
    "client/linux/resources/auditd/conf/suse12_audit.rules"
    "client/linux/resources/auditd/conf/suse12_sp5_audit.rules"
    "client/linux/resources/auditd/setup/ubuntu20/auditd_2.8.5-2ubuntu6_amd64.deb"
    "client/linux/resources/auditd/setup/ubuntu20/libauparse0_2.8.5-2ubuntu6_amd64.deb"
    "client/linux/resources/auditd/setup/ubuntu22/auditd_3.0.7-1build1_amd64.deb"
    "client/linux/resources/auditd/setup/ubuntu22/libauparse0_3.0.7-1build1_amd64.deb"
    "client/linux/resources/auditd/setup/ubuntu2404/auditd_3.1.2-2.1build1.1_amd64.deb"
    "client/linux/resources/auditd/setup/ubuntu2404/libauparse0t64_3.1.2-2.1build1.1_amd64.deb"
    "client/linux/resources/auditd/setup/oracle_rhel_centos7/audit-2.8.5-4.el7.x86_64.rpm"
    "client/linux/resources/auditd/setup/oracle_rhel_centos7/audit-libs-2.8.5-4.el7.x86_64.rpm"
  )

  for relative_path in "${required_files[@]}"; do
    download_file "${base_url}/${relative_path}" "${bootstrap_root}/${relative_path}"
  done
}

if [[ ! -f "$IMPLEMENTATION" ]]; then
  BOOTSTRAP_ROOT="${INSTALL_ROOT}/bootstrap"
  log_bootstrap "Local client/linux payload not found. Bootstrapping into ${BOOTSTRAP_ROOT}"
  ensure_bootstrap_payload "$BOOTSTRAP_BASE_URL" "$BOOTSTRAP_ROOT"
  IMPLEMENTATION="${BOOTSTRAP_ROOT}/client/linux/elastic-agent-ncs-linux-standalone-install.sh"
fi

if [[ ! -f "$IMPLEMENTATION" ]]; then
  printf 'Installer implementation not found after bootstrap: %s\n' "$IMPLEMENTATION" >&2
  exit 1
fi

exec bash "$IMPLEMENTATION" \
  --artifact-base-url "$ARTIFACT_BASE_URL" \
  --bootstrap-base-url "$BOOTSTRAP_BASE_URL" \
  "${ARGS[@]}"

