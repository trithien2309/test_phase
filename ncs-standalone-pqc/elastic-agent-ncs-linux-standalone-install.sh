#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_BASE_URL="https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages"
BOOTSTRAP_BASE_URL="https://github.com/trithien2309/test_phase/raw/main/ncs-standalone-pqc"
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

detect_bootstrap_profile() {
  local os_id=""
  local os_like=""
  local os_major=0

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    local version_id="${VERSION_ID:-0}"
    os_id="${ID:-}"
    os_like="${ID_LIKE:-}"
    os_major="${version_id%%.*}"
    [[ "$os_major" =~ ^[0-9]+$ ]] || os_major=0
  fi

  printf '%s|%s|%s\n' "$os_id" "$os_like" "$os_major"
}

bootstrap_auditd_rule_for_host() {
  local os_id="$1"
  local os_like="$2"
  local os_major="$3"

  if [[ "$os_id" == "ubuntu" ]]; then
    (( os_major >= 20 )) || return 1
    printf '%s\n' "client/linux/resources/auditd/conf/ubuntu_audit.rules"
    return 0
  fi

  if [[ "$os_id" == "debian" ]]; then
    (( os_major >= 10 )) || return 1
    printf '%s\n' "client/linux/resources/auditd/conf/ubuntu_audit.rules"
    return 0
  fi

  if [[ "$os_id" =~ ^(rhel|centos|rocky|almalinux|ol|oracle)$ ]] || [[ "$os_like" == *"rhel"* ]] || [[ "$os_like" == *"fedora"* ]]; then
    (( os_major >= 7 )) || return 1
    printf '%s\n' "client/linux/resources/auditd/conf/centos_audit.rules"
    return 0
  fi

  return 1
}

ensure_bootstrap_payload() {
  local base_url="${1%/}"
  local bootstrap_root="$2"
  local selected_rule="$3"
  local required_files=(
    "client/linux/elastic-agent-ncs-linux-standalone-install.sh"
    "client/linux/packages/manifest.json"
    "client/linux/packages/SHA256SUMS.txt"
  )

  for relative_path in "${required_files[@]}"; do
    download_file "${base_url}/${relative_path}" "${bootstrap_root}/${relative_path}"
  done

  if [[ -n "$selected_rule" ]]; then
    download_file "${base_url}/${selected_rule}" "${bootstrap_root}/${selected_rule}"
  fi
}

if [[ ! -f "$IMPLEMENTATION" ]]; then
  BOOTSTRAP_ROOT="${INSTALL_ROOT}/bootstrap"
  log_bootstrap "Local client/linux payload not found. Bootstrapping into ${BOOTSTRAP_ROOT}"
  IFS='|' read -r BOOTSTRAP_ID BOOTSTRAP_ID_LIKE BOOTSTRAP_MAJOR <<< "$(detect_bootstrap_profile)"
  BOOTSTRAP_SELECTED_RULE="$(bootstrap_auditd_rule_for_host "$BOOTSTRAP_ID" "$BOOTSTRAP_ID_LIKE" "$BOOTSTRAP_MAJOR" || true)"
  if [[ -z "$BOOTSTRAP_SELECTED_RULE" ]]; then
    printf 'Unsupported Linux distro for bootstrap: ID=%s VERSION=%s\n' "$BOOTSTRAP_ID" "$BOOTSTRAP_MAJOR" >&2
    exit 1
  fi
  ensure_bootstrap_payload "$BOOTSTRAP_BASE_URL" "$BOOTSTRAP_ROOT" "$BOOTSTRAP_SELECTED_RULE"
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
