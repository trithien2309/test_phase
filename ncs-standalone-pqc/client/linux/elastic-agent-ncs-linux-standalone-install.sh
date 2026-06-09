#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_BASE_URL="https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages"
BOOTSTRAP_BASE_URL="https://github.com/trithien2309/test_phase/raw/main/ncs-standalone-pqc"
ARTIFACT_PRIVATE_TOKEN=""
AGENT_PACKAGE=""
FILEBEAT_PQC_PACKAGE=""
AUDITD_BUNDLE=""
INSTALL_ROOT="/opt/ncs-elastic-agent-standalone"
GATEWAY_HOST="192.168.22.171"
GATEWAY_PORT="5443"
SMOKE_LOG="/var/log/ncs-agent-smoke.log"
ALLOW_GATEWAY_OFFLINE=0
VERIFY_ONLY_AUDITD=0

AGENT_PACKAGE_NAMES=("ncs-elastic-agent-pqc-linux-amd64.tar.gz")
FILEBEAT_PACKAGE_NAMES=("filebeat-pqc-linux-amd64.tar.gz")
AUDITD_BUNDLE_NAMES=("ncs-linux-auditd-v3.7.8-minimal.tar.gz")
MANIFEST_NAME="manifest.json"
SHA256_NAME="SHA256SUMS.txt"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR=""
LOGS_DIR=""
AGENT_DIR=""
FILEBEAT_DIR=""
AUDITD_DIR=""
AGENT_BIN=""
FILEBEAT_BIN=""
AGENT_CONFIG=""
DETECTED_ID=""
DETECTED_ID_LIKE=""
DETECTED_VERSION=""
DETECTED_MAJOR=0
DETECTED_ARCH=""
AUDITD_RULE_SOURCE=""
AUDITD_PROFILE=""

usage() {
  cat <<'USAGE'
Usage:
  sudo bash elastic-agent-ncs-linux-standalone-install.sh \
    --gateway-host 192.168.22.171 \
    --gateway-port 5443

Options:
  --artifact-base-url URL
  --bootstrap-base-url URL
  --artifact-private-token TOKEN
  --agent-package PATH
  --filebeat-pqc-package PATH
  --auditd-bundle PATH
  --install-root PATH
  --gateway-host HOST
  --gateway-port PORT
  --smoke-log PATH
  --allow-gateway-offline
  --verify-only-auditd
USAGE
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    printf 'Missing value for %s\n' "$option" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-base-url)
      require_value "$1" "${2:-}"
      ARTIFACT_BASE_URL="$2"
      shift 2
      ;;
    --artifact-base-url=*)
      ARTIFACT_BASE_URL="${1#*=}"
      shift
      ;;
    --bootstrap-base-url)
      require_value "$1" "${2:-}"
      BOOTSTRAP_BASE_URL="$2"
      shift 2
      ;;
    --bootstrap-base-url=*)
      BOOTSTRAP_BASE_URL="${1#*=}"
      shift
      ;;
    --artifact-private-token)
      require_value "$1" "${2:-}"
      ARTIFACT_PRIVATE_TOKEN="$2"
      shift 2
      ;;
    --artifact-private-token=*)
      ARTIFACT_PRIVATE_TOKEN="${1#*=}"
      shift
      ;;
    --agent-package)
      require_value "$1" "${2:-}"
      AGENT_PACKAGE="$2"
      shift 2
      ;;
    --agent-package=*)
      AGENT_PACKAGE="${1#*=}"
      shift
      ;;
    --filebeat-pqc-package)
      require_value "$1" "${2:-}"
      FILEBEAT_PQC_PACKAGE="$2"
      shift 2
      ;;
    --filebeat-pqc-package=*)
      FILEBEAT_PQC_PACKAGE="${1#*=}"
      shift
      ;;
    --auditd-bundle)
      require_value "$1" "${2:-}"
      AUDITD_BUNDLE="$2"
      shift 2
      ;;
    --auditd-bundle=*)
      AUDITD_BUNDLE="${1#*=}"
      shift
      ;;
    --install-root)
      require_value "$1" "${2:-}"
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --install-root=*)
      INSTALL_ROOT="${1#*=}"
      shift
      ;;
    --gateway-host)
      require_value "$1" "${2:-}"
      GATEWAY_HOST="$2"
      shift 2
      ;;
    --gateway-host=*)
      GATEWAY_HOST="${1#*=}"
      shift
      ;;
    --gateway-port)
      require_value "$1" "${2:-}"
      GATEWAY_PORT="$2"
      shift 2
      ;;
    --gateway-port=*)
      GATEWAY_PORT="${1#*=}"
      shift
      ;;
    --smoke-log)
      require_value "$1" "${2:-}"
      SMOKE_LOG="$2"
      shift 2
      ;;
    --smoke-log=*)
      SMOKE_LOG="${1#*=}"
      shift
      ;;
    --allow-gateway-offline)
      ALLOW_GATEWAY_OFFLINE=1
      shift
      ;;
    --verify-only-auditd)
      VERIFY_ONLY_AUDITD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

INSTALL_ROOT="${INSTALL_ROOT%/}"
PACKAGES_DIR="${INSTALL_ROOT}/packages"
LOGS_DIR="${INSTALL_ROOT}/logs"
AGENT_DIR="${INSTALL_ROOT}/agent"
FILEBEAT_DIR="${INSTALL_ROOT}/filebeat"
AUDITD_DIR="${INSTALL_ROOT}/auditd"
FILEBEAT_BIN="${FILEBEAT_DIR}/filebeat-pqc-linux-amd64"
AGENT_CONFIG="${AGENT_DIR}/elastic-agent.yml"

phase() {
  printf '\n%s\n' "$1"
}

info() {
  printf '  [INFO] %s\n' "$1" >&2
}

ok() {
  printf '  [OK] %s\n' "$1" >&2
}

warn() {
  printf '  [WARN] %s\n' "$1" >&2
}

fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  exit 1
}

run_or_warn() {
  local description="$1"
  shift
  if "$@"; then
    ok "$description"
  else
    warn "$description failed"
  fi
}

download_file() {
  local uri="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  info "Downloading ${uri}"
  if [[ -n "$ARTIFACT_PRIVATE_TOKEN" ]]; then
    curl -fL --retry 2 --retry-delay 2 -H "PRIVATE-TOKEN: ${ARTIFACT_PRIVATE_TOKEN}" -o "$destination" "$uri" || return 1
  else
    curl -fL --retry 2 --retry-delay 2 -o "$destination" "$uri" || return 1
  fi
}

try_download_file() {
  local uri="$1"
  local destination="$2"
  if download_file "$uri" "$destination"; then
    return 0
  fi
  rm -f "$destination"
  return 1
}

copy_or_download_metadata() {
  local name="$1"
  local destination="${PACKAGES_DIR}/${name}"
  local local_source="${SCRIPT_DIR}/packages/${name}"

  if [[ -f "$local_source" ]]; then
    cp "$local_source" "$destination"
    ok "Metadata found locally: ${name}"
    return 0
  fi

  if try_download_file "${ARTIFACT_BASE_URL%/}/${name}" "$destination"; then
    ok "Metadata downloaded: ${name}"
    return 0
  fi

  warn "Metadata not available: ${name}"
  return 1
}

expected_sha_for() {
  local name="$1"
  local sums="${PACKAGES_DIR}/${SHA256_NAME}"
  if [[ ! -f "$sums" ]]; then
    return 0
  fi
  awk -v n="$name" 'tolower($2)==tolower(n){print toupper($1); exit}' "$sums"
}

verify_sha_if_known() {
  local path="$1"
  local name
  name="$(basename "$path")"
  local expected
  expected="$(expected_sha_for "$name" || true)"
  if [[ -z "$expected" ]]; then
    warn "SHA256SUMS.txt has no hash for ${name}; skipping hash verification"
    return 0
  fi

  local actual
  actual="$(sha256sum "$path" | awk '{print toupper($1)}')"
  if [[ "$actual" != "$expected" ]]; then
    fail "SHA256 mismatch for ${name}. expected=${expected} actual=${actual}"
  fi
  ok "SHA256 verified: ${name}"
}

show_manifest_info() {
  local manifest="${PACKAGES_DIR}/${MANIFEST_NAME}"
  if [[ -f "$manifest" ]]; then
    info "Manifest: $(tr -d '\n' < "$manifest" | sed 's/[[:space:]]\+/ /g' | cut -c1-180)"
  fi
}

resolve_artifact() {
  local provided="$1"
  shift
  local names=("$@")

  if [[ -n "$provided" ]]; then
    [[ -f "$provided" ]] || fail "Local artifact not found: ${provided}"
    local destination="${PACKAGES_DIR}/$(basename "$provided")"
    cp "$provided" "$destination"
    verify_sha_if_known "$destination"
    printf '%s\n' "$destination"
    return 0
  fi

  local name source destination
  for name in "${names[@]}"; do
    for source in "${SCRIPT_DIR}/packages/${name}" "${PACKAGES_DIR}/${name}"; do
      if [[ -f "$source" ]]; then
        destination="${PACKAGES_DIR}/${name}"
        if [[ "$source" != "$destination" ]]; then
          cp "$source" "$destination"
        fi
        verify_sha_if_known "$destination"
        printf '%s\n' "$destination"
        return 0
      fi
    done
  done

  for name in "${names[@]}"; do
    destination="${PACKAGES_DIR}/${name}"
    if try_download_file "${ARTIFACT_BASE_URL%/}/${name}" "$destination"; then
      verify_sha_if_known "$destination"
      printf '%s\n' "$destination"
      return 0
    fi
  done

  fail "Could not resolve artifact. Tried: ${names[*]}"
}

resolve_optional_artifact() {
  local provided="$1"
  shift
  local names=("$@")

  if [[ -n "$provided" ]]; then
    [[ -f "$provided" ]] || fail "Local artifact not found: ${provided}"
    local destination="${PACKAGES_DIR}/$(basename "$provided")"
    cp "$provided" "$destination"
    verify_sha_if_known "$destination"
    printf '%s\n' "$destination"
    return 0
  fi

  local name source destination
  for name in "${names[@]}"; do
    for source in "${SCRIPT_DIR}/packages/${name}" "${PACKAGES_DIR}/${name}"; do
      if [[ -f "$source" ]]; then
        destination="${PACKAGES_DIR}/${name}"
        if [[ "$source" != "$destination" ]]; then
          cp "$source" "$destination"
        fi
        verify_sha_if_known "$destination"
        printf '%s\n' "$destination"
        return 0
      fi
    done
  done

  for name in "${names[@]}"; do
    destination="${PACKAGES_DIR}/${name}"
    if try_download_file "${ARTIFACT_BASE_URL%/}/${name}" "$destination"; then
      verify_sha_if_known "$destination"
      printf '%s\n' "$destination"
      return 0
    fi
  done

  return 1
}

extract_archive() {
  local archive="$1"
  local destination="$2"
  mkdir -p "$destination"
  case "$archive" in
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$destination"
      ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || fail "unzip is required to extract ${archive}"
      unzip -q "$archive" -d "$destination"
      ;;
    *)
      fail "Unsupported archive type: ${archive}"
      ;;
  esac
}

assert_safe_install_subdir() {
  local path="$1"
  case "$path" in
    "${INSTALL_ROOT}"/*) ;;
    *) fail "Refusing to modify path outside install root: ${path}" ;;
  esac
}

reset_install_subdir() {
  local path="$1"
  assert_safe_install_subdir "$path"
  rm -rf "$path"
  mkdir -p "$path"
}

extract_agent_package() {
  local archive="$1"
  local tmp
  tmp="$(mktemp -d)"
  extract_archive "$archive" "$tmp"

  local bin
  bin="$(find "$tmp" -type f -name elastic-agent | head -n 1 || true)"
  [[ -n "$bin" ]] || fail "elastic-agent binary not found in ${archive}"

  reset_install_subdir "$AGENT_DIR"
  cp -a "$(dirname "$bin")"/. "$AGENT_DIR"/
  chmod +x "${AGENT_DIR}/elastic-agent"
  AGENT_BIN="${AGENT_DIR}/elastic-agent"
  rm -rf "$tmp"
  ok "Elastic Agent binary: ${AGENT_BIN}"
}

extract_filebeat_package() {
  local archive="$1"
  local tmp
  tmp="$(mktemp -d)"
  extract_archive "$archive" "$tmp"

  local bin
  bin="$(find "$tmp" -type f \( -name 'filebeat' -o -name 'filebeat-*' \) | head -n 1 || true)"
  [[ -n "$bin" ]] || fail "filebeat binary not found in ${archive}"

  reset_install_subdir "$FILEBEAT_DIR"
  cp "$bin" "$FILEBEAT_BIN"
  chmod +x "$FILEBEAT_BIN"
  rm -rf "$tmp"
  ok "Filebeat PQC binary: ${FILEBEAT_BIN}"
}

prepare_auditd_resources() {
  local bundle="$1"
  reset_install_subdir "$AUDITD_DIR"
  if [[ -n "$bundle" ]]; then
    extract_archive "$bundle" "$AUDITD_DIR"
    ok "Auditd bundle extracted: ${AUDITD_DIR}"
    return
  fi

  local resource_root="${SCRIPT_DIR}/resources/auditd"
  [[ -d "$resource_root" ]] || fail "Auditd resources not found: ${resource_root}"
  cp -a "$resource_root"/. "$AUDITD_DIR"/
  ok "Auditd resources copied from client/linux/resources"
}

read_os_release() {
  [[ -f /etc/os-release ]] || fail "/etc/os-release not found"
  # shellcheck disable=SC1091
  . /etc/os-release
  DETECTED_ID="${ID:-}"
  DETECTED_ID_LIKE="${ID_LIKE:-}"
  DETECTED_VERSION="${VERSION_ID:-}"
  DETECTED_MAJOR="${DETECTED_VERSION%%.*}"
  [[ "$DETECTED_MAJOR" =~ ^[0-9]+$ ]] || DETECTED_MAJOR=0
  DETECTED_ARCH="$(uname -m)"
}

is_rhel_like() {
  [[ "$DETECTED_ID" =~ ^(rhel|centos|rocky|almalinux|ol|oracle)$ ]] || [[ "$DETECTED_ID_LIKE" == *"rhel"* ]] || [[ "$DETECTED_ID_LIKE" == *"fedora"* ]]
}

select_auditd_profile() {
  AUDITD_PROFILE=""
  AUDITD_RULE_SOURCE=""

  if [[ "$DETECTED_ID" == "ubuntu" ]]; then
    if (( DETECTED_MAJOR < 20 )); then
      fail "Ubuntu ${DETECTED_VERSION} is unsupported in Linux v1. Use Ubuntu 20.04+."
    fi
    AUDITD_PROFILE="ubuntu"
    AUDITD_RULE_SOURCE="${AUDITD_DIR}/conf/ubuntu_audit.rules"
  elif [[ "$DETECTED_ID" == "debian" ]]; then
    if (( DETECTED_MAJOR < 10 )); then
      fail "Debian ${DETECTED_VERSION} is unsupported in Linux v1. Use Debian 10+."
    fi
    AUDITD_PROFILE="debian"
    AUDITD_RULE_SOURCE="${AUDITD_DIR}/conf/ubuntu_audit.rules"
  elif is_rhel_like; then
    if (( DETECTED_MAJOR < 7 )); then
      fail "${DETECTED_ID} ${DETECTED_VERSION} is unsupported in Linux v1. Use EL7+."
    fi
    AUDITD_PROFILE="rhel"
    AUDITD_RULE_SOURCE="${AUDITD_DIR}/conf/centos_audit.rules"
  else
    fail "Unsupported Linux distro: ID=${DETECTED_ID} VERSION_ID=${DETECTED_VERSION}"
  fi

  [[ -f "$AUDITD_RULE_SOURCE" ]] || fail "Audit rule file not found: ${AUDITD_RULE_SOURCE}"
  ok "Linux profile: id=${DETECTED_ID} version=${DETECTED_VERSION} arch=${DETECTED_ARCH} audit_profile=${AUDITD_PROFILE}"
}

auditd_exists() {
  command -v auditd >/dev/null 2>&1 || [[ -x /sbin/auditd ]] || [[ -x /usr/sbin/auditd ]]
}

install_auditd_ubuntu_offline() {
  local setup_dir=""
  case "$DETECTED_MAJOR" in
    20) setup_dir="${AUDITD_DIR}/setup/ubuntu20" ;;
    22) setup_dir="${AUDITD_DIR}/setup/ubuntu22" ;;
    24) setup_dir="${AUDITD_DIR}/setup/ubuntu2404" ;;
  esac

  if [[ -n "$setup_dir" && -d "$setup_dir" ]]; then
    info "Installing auditd from offline packages: ${setup_dir}"
    if dpkg -i "$setup_dir"/*.deb; then
      return 0
    fi
    warn "Offline dpkg install did not complete cleanly"
  fi
  return 1
}

install_auditd_rhel() {
  if [[ "$DETECTED_MAJOR" == "7" && -d "${AUDITD_DIR}/setup/oracle_rhel_centos7" ]]; then
    info "Installing auditd from EL7 rpm bundle"
    if rpm -Uvh --replacepkgs "${AUDITD_DIR}/setup/oracle_rhel_centos7"/*.rpm; then
      return 0
    fi
    warn "Offline rpm install did not complete cleanly"
  fi

  if command -v dnf >/dev/null 2>&1; then
    dnf install -y audit audit-libs
  elif command -v yum >/dev/null 2>&1; then
    yum install -y audit audit-libs
  else
    return 1
  fi
}

install_or_verify_auditd() {
  select_auditd_profile

  if auditd_exists; then
    ok "auditd already installed"
  else
    case "$AUDITD_PROFILE" in
      ubuntu)
        install_auditd_ubuntu_offline || {
          warn "Offline auditd install failed or packages missing; trying apt-get"
          apt-get update
          apt-get install -y auditd audispd-plugins || apt-get install -y auditd
        }
        ;;
      debian)
        apt-get update
        apt-get install -y auditd audispd-plugins || apt-get install -y auditd
        ;;
      rhel)
        install_auditd_rhel || fail "Could not install auditd on ${DETECTED_ID}"
        ;;
    esac
  fi

  [[ -f /etc/audit/auditd.conf ]] || fail "/etc/audit/auditd.conf not found after auditd install"
  mkdir -p /etc/audit/rules.d
  ok "auditd verified"
}

set_auditd_conf() {
  local key="$1"
  local value="$2"
  local file="/etc/audit/auditd.conf"

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    printf '%s = %s\n' "$key" "$value" >> "$file"
  fi
}

configure_auditd_policy() {
  local report="${LOGS_DIR}/auditd-check.log"
  : > "$report"

  {
    printf '[INFO] distro=%s version=%s profile=%s\n' "$DETECTED_ID" "$DETECTED_VERSION" "$AUDITD_PROFILE"
    printf '[INFO] rule_source=%s\n' "$AUDITD_RULE_SOURCE"
  } >> "$report"

  if [[ "$VERIFY_ONLY_AUDITD" == "1" ]]; then
    warn "Verify-only auditd mode enabled. Local auditd policy will not be changed."
    auditctl -s >> "$report" 2>&1 || true
    auditctl -l | head -n 80 >> "$report" 2>&1 || true
    ok "Auditd verification report: ${report}"
    return
  fi

  local timestamp
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  [[ -f /etc/audit/auditd.conf ]] && cp /etc/audit/auditd.conf "/etc/audit/auditd.conf.${timestamp}.bak"
  [[ -f /etc/audit/rules.d/audit.rules ]] && cp /etc/audit/rules.d/audit.rules "/etc/audit/rules.d/audit.rules.${timestamp}.bak"

  cp "$AUDITD_RULE_SOURCE" /etc/audit/rules.d/audit.rules
  set_auditd_conf "log_format" "ENRICHED"
  set_auditd_conf "max_log_file" "256"
  set_auditd_conf "num_logs" "5"
  set_auditd_conf "max_log_file_action" "ROTATE"
  set_auditd_conf "disk_full_action" "SUSPEND"

  augenrules --load >> "$report" 2>&1 || warn "augenrules --load returned non-zero; check ${report}"
  systemctl enable auditd >> "$report" 2>&1 || warn "Could not enable auditd"
  service auditd restart >> "$report" 2>&1 || systemctl restart auditd >> "$report" 2>&1 || warn "Could not restart auditd"

  auditctl -s >> "$report" 2>&1 || true
  auditctl -l | head -n 120 >> "$report" 2>&1 || true
  [[ -e /var/log/audit/audit.log ]] || warn "/var/log/audit/audit.log does not exist yet; auditd may create it after first event"
  ok "Auditd policy configured. Report: ${report}"
}

write_testbeat_spec() {
  local destination="$1"
  cat > "$destination" <<'YAML'
version: 2
inputs:
  - name: filestream
    description: "Filestream"
    platforms: &platforms
      - linux/amd64
    outputs: &outputs
      - elasticsearch
      - kafka
      - logstash
      - redis
    command: &command
      name: "filebeat"
      restart_monitoring_period: 5s
      maximum_restarts_per_period: 1
      timeouts:
        restart: 1s
      args:
        - "-E"
        - "setup.ilm.enabled=false"
        - "-E"
        - "setup.template.enabled=false"
        - "-E"
        - "management.enabled=true"
        - "-E"
        - "management.restart_on_output_change=true"
        - "-E"
        - "logging.level=info"
        - "-E"
        - "logging.to_stderr=true"
        - "-E"
        - "filebeat.config.modules.enabled=false"
        - "-E"
        - "logging.event_data.to_stderr=true"
        - "-E"
        - "logging.event_data.to_files=false"
YAML
}

agent_build_info() {
  local version="9.5.0"
  local commit="unknown"
  local out
  out="$("$AGENT_BIN" version --binary-only 2>&1 || true)"
  if [[ "$out" =~ Binary:[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+(-SNAPSHOT)?) ]]; then
    version="${BASH_REMATCH[1]}"
  fi
  if [[ "$out" =~ commit[[:space:]]+([A-Za-z0-9]+) ]]; then
    commit="${BASH_REMATCH[1]}"
  fi
  local short_commit="$commit"
  if (( ${#short_commit} > 6 )); then
    short_commit="${short_commit:0:6}"
  fi
  printf '%s|%s|%s|data/elastic-agent-%s-%s\n' "$version" "$commit" "$short_commit" "$version" "$short_commit"
}

ensure_agent_package_layout() {
  local build version commit versioned_home components_dir
  build="$(agent_build_info)"
  IFS='|' read -r version commit _ versioned_home <<< "$build"
  components_dir="${AGENT_DIR}/${versioned_home}/components"

  mkdir -p "$components_dir"
  cp "$AGENT_BIN" "${AGENT_DIR}/${versioned_home}/elastic-agent"
  cp "$FILEBEAT_BIN" "${components_dir}/testbeat"
  chmod +x "${AGENT_DIR}/${versioned_home}/elastic-agent" "${components_dir}/testbeat"

  write_testbeat_spec "${components_dir}/testbeat.spec.yml"
  printf '%s\n' "$version" > "${AGENT_DIR}/package.version"

  cat > "${AGENT_DIR}/manifest.yaml" <<YAML
apiVersion: v1
kind: PackageManifest
package:
  version: ${version}
  snapshot: false
  hash: ${commit}
  versioned-home: ${versioned_home}
  flavors:
    basic:
      - testbeat
    servers:
      - testbeat
  path-mappings:
    - ${versioned_home}: ${versioned_home}
      manifest.yaml: ${versioned_home}/manifest.yaml
YAML
  cp "${AGENT_DIR}/manifest.yaml" "${AGENT_DIR}/${versioned_home}/manifest.yaml"
  ok "Elastic Agent package layout is ready"
}

write_agent_config() {
  local logstash_host="${GATEWAY_HOST}:${GATEWAY_PORT}"
  mkdir -p "$(dirname "$SMOKE_LOG")"
  if [[ ! -f "$SMOKE_LOG" ]]; then
    printf 'ncs-linux-bootstrap %s %s\n' "$(date -Iseconds)" "$(printf 'A%.0s' {1..1600})" > "$SMOKE_LOG"
  fi

  cat > "$AGENT_CONFIG" <<YAML
agent:
  logging:
    level: debug
    to_stderr: true
    to_files: true
  monitoring:
    enabled: false
  internal:
    runtime:
      output:
        logstash: process

outputs:
  default:
    type: logstash
    hosts: ["${logstash_host}"]
    ssl.enabled: true
    ssl.verification_mode: none
    ssl.curve_types: ["X25519MLKEM768"]
    ssl.supported_protocols: ["TLSv1.3"]
    ssl.strict_pqc: true

inputs:
  - id: ncs-linux-auditd
    type: filestream
    use_output: default
    data_stream:
      namespace: default
    streams:
      - id: ncs-linux-auditd-stream
        data_stream:
          type: logs
          dataset: ncs.linux.auditd
        paths:
          - /var/log/audit/audit.log

  - id: ncs-linux-system-logs
    type: filestream
    use_output: default
    data_stream:
      namespace: default
    streams:
      - id: ncs-linux-auth
        data_stream:
          type: logs
          dataset: ncs.linux.auth
        paths:
          - /var/log/auth.log
          - /var/log/secure

      - id: ncs-linux-syslog
        data_stream:
          type: logs
          dataset: ncs.linux.syslog
        paths:
          - /var/log/syslog
          - /var/log/messages

      - id: ncs-linux-package
        data_stream:
          type: logs
          dataset: ncs.linux.package
        paths:
          - /var/log/dpkg.log
          - /var/log/apt/history.log
          - /var/log/yum.log
          - /var/log/dnf.log

      - id: ncs-linux-smoke
        data_stream:
          type: logs
          dataset: ncs.transport_smoke
        paths:
          - ${SMOKE_LOG}
YAML
  ok "Standalone Elastic Agent config written: ${AGENT_CONFIG}"
}

write_pqc_environment() {
  mkdir -p /etc/ncs-elastic-agent
  cat > /etc/ncs-elastic-agent/pqc.env <<EOF
PQC_FILEBEAT_BIN=${FILEBEAT_BIN}
LOGSTASH_TLS_CURVE_TYPES=X25519MLKEM768
LOGSTASH_TLS_MIN_VERSION=1.3
LOGSTASH_TLS_STRICT_PQC=true
EOF

  mkdir -p /etc/systemd/system/elastic-agent.service.d
  cat > /etc/systemd/system/elastic-agent.service.d/10-ncs-pqc.conf <<'EOF'
[Service]
EnvironmentFile=/etc/ncs-elastic-agent/pqc.env
EOF
  ok "PQC systemd environment configured"
}

install_elastic_agent_service() {
  info "Running Elastic Agent install in standalone mode. No Fleet URL/token is used."
  (cd "$AGENT_DIR" && ./elastic-agent install --force --non-interactive)
  systemctl daemon-reload
  systemctl restart elastic-agent
  ok "Elastic Agent service installed/restarted"
}

test_tcp_port() {
  local host="$1"
  local port="$2"

  if command -v nc >/dev/null 2>&1; then
    nc -z -w 3 "$host" "$port"
    return $?
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
    return $?
  fi

  bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
}

preflight() {
  [[ "$(id -u)" == "0" ]] || fail "Run this script as root with sudo."
  [[ "$(uname -s)" == "Linux" ]] || fail "This installer is Linux-only."
  read_os_release
  [[ "$DETECTED_ARCH" == "x86_64" || "$DETECTED_ARCH" == "amd64" ]] || fail "Linux v1 requires x86_64/amd64. Detected: ${DETECTED_ARCH}"
  command -v systemctl >/dev/null 2>&1 || fail "systemd/systemctl is required."
  command -v curl >/dev/null 2>&1 || fail "curl is required."
  command -v tar >/dev/null 2>&1 || fail "tar is required."

  mkdir -p "$PACKAGES_DIR" "$LOGS_DIR" "$AGENT_DIR" "$FILEBEAT_DIR" "$AUDITD_DIR"
  ok "Linux x86_64 detected: ${DETECTED_ID} ${DETECTED_VERSION}"
  info "Install root: ${INSTALL_ROOT}"
  info "PQC Gateway: ${GATEWAY_HOST}:${GATEWAY_PORT}"

  if test_tcp_port "$GATEWAY_HOST" "$GATEWAY_PORT"; then
    ok "TCP reachable: ${GATEWAY_HOST}:${GATEWAY_PORT}"
  elif [[ "$ALLOW_GATEWAY_OFFLINE" == "1" ]]; then
    warn "Gateway is not reachable now. Continuing because --allow-gateway-offline is set."
  else
    fail "PQC Gateway is not reachable: ${GATEWAY_HOST}:${GATEWAY_PORT}. Start gateway or use --allow-gateway-offline."
  fi
}

remove_existing_elastic_agent() {
  systemctl stop elastic-agent >/dev/null 2>&1 || true

  local candidates=(
    "/opt/Elastic/Agent/elastic-agent"
    "/usr/share/elastic-agent/elastic-agent"
    "/usr/bin/elastic-agent"
    "${AGENT_DIR}/elastic-agent"
  )

  local bin
  for bin in "${candidates[@]}"; do
    if [[ -x "$bin" ]]; then
      info "Trying uninstall with ${bin}"
      "$bin" uninstall --force >/dev/null 2>&1 || "$bin" uninstall -f >/dev/null 2>&1 || true
    fi
  done

  if systemctl list-unit-files elastic-agent.service >/dev/null 2>&1; then
    systemctl disable --now elastic-agent >/dev/null 2>&1 || true
  fi
  rm -rf /etc/systemd/system/elastic-agent.service.d
  systemctl daemon-reload >/dev/null 2>&1 || true
  ok "Existing Elastic Agent cleanup completed"
}

verify_local_state() {
  local report="${LOGS_DIR}/local-verify.log"
  : > "$report"

  {
    printf 'Elastic Agent service:\n'
    systemctl status elastic-agent --no-pager || true
    printf '\nAuditd service:\n'
    systemctl status auditd --no-pager || true
    printf '\nFilebeat process:\n'
    pgrep -a filebeat || true
    printf '\nPQC env:\n'
    cat /etc/ncs-elastic-agent/pqc.env 2>/dev/null || true
  } >> "$report" 2>&1

  systemctl is-active --quiet elastic-agent && ok "Elastic Agent service is running" || warn "Elastic Agent service is not running"
  systemctl is-active --quiet auditd && ok "auditd service is running" || warn "auditd service is not running"

  if pgrep -af "filebeat-pqc-linux-amd64" >/dev/null 2>&1; then
    ok "Filebeat PQC process found"
  else
    warn "Filebeat PQC process not found yet"
  fi

  printf 'ncs-linux-manual-event %s %s\n' "$(date -Iseconds)" "$(printf 'A%.0s' {1..1600})" >> "$SMOKE_LOG"
  ok "Smoke event appended: ${SMOKE_LOG}"

  local log_root="/opt/Elastic/Agent/data"
  if [[ -d "$log_root" ]]; then
    grep -RhiE "pqc_mode|TLS handshake completed|configured_curve_preferences|strict_pqc" "$log_root" 2>/dev/null | tail -n 40 >> "$report" || true
  fi
  ok "Local verification report: ${report}"

  cat <<EOF

Server-side checks:
  ss -lntp | grep -E ':${GATEWAY_PORT}|:5044'
  journalctl -u siem-pqc-gateway -f

Kibana queries:
  data_stream.dataset : "ncs.linux.auditd"
  data_stream.dataset : "ncs.linux.auth"
  data_stream.dataset : "ncs.linux.syslog"
  data_stream.dataset : "ncs.linux.package"
EOF
}

printf '\n====================================================\n'
printf '  NCS Elastic Agent PQC Linux Standalone Installer\n'
printf '====================================================\n'

phase "[0/9] Preflight"
preflight

phase "[1/9] Remove existing Elastic Agent"
remove_existing_elastic_agent

phase "[2/9] Download or use local PQC artifacts"
copy_or_download_metadata "$MANIFEST_NAME" || true
copy_or_download_metadata "$SHA256_NAME" || true
show_manifest_info
AGENT_ARCHIVE="$(resolve_artifact "$AGENT_PACKAGE" "${AGENT_PACKAGE_NAMES[@]}")"
FILEBEAT_ARCHIVE="$(resolve_artifact "$FILEBEAT_PQC_PACKAGE" "${FILEBEAT_PACKAGE_NAMES[@]}")"
AUDITD_ARCHIVE="$(resolve_optional_artifact "$AUDITD_BUNDLE" "${AUDITD_BUNDLE_NAMES[@]}" || true)"

phase "[3/9] Extract PQC and auditd artifacts"
extract_agent_package "$AGENT_ARCHIVE"
extract_filebeat_package "$FILEBEAT_ARCHIVE"
prepare_auditd_resources "$AUDITD_ARCHIVE"

phase "[4/9] Install or verify auditd"
install_or_verify_auditd

phase "[5/9] Configure Linux audit policy"
configure_auditd_policy

phase "[6/9] Create Elastic Agent standalone config"
ensure_agent_package_layout
write_agent_config

phase "[7/9] Set systemd PQC environment"
write_pqc_environment

phase "[8/9] Install Elastic Agent service"
install_elastic_agent_service

phase "[9/9] Verify local"
verify_local_state

printf '\nNCS Elastic Agent PQC Linux install flow completed.\n'
