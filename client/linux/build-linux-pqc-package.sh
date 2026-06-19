#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
OUTPUT_DIR="${SOURCE_ROOT}/publish/linux-pqc-build"
VERSION=""
COMMIT=""
SKIP_BUILD=0
AGENT_BINARY=""
FILEBEAT_BINARY=""

usage() {
  cat <<'USAGE'
Usage:
  bash client/linux/build-linux-pqc-package.sh [options]

Options:
  --source-root PATH       Elastic Agent source root. Defaults to this repo.
  --output-dir PATH        Output directory for build/package artifacts.
  --version VERSION        Package version. Defaults to version/version.go defaultBeatVersion.
  --commit COMMIT          Package commit/hash. Defaults to the Git short commit.
  --agent-binary PATH      Use existing Linux elastic-agent binary.
  --filebeat-binary PATH   Use existing Linux filebeat PQC binary.
  --skip-build             Package existing binaries only.
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
    --source-root)
      require_value "$1" "${2:-}"
      SOURCE_ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    --source-root=*)
      SOURCE_ROOT="$(cd "${1#*=}" && pwd)"
      shift
      ;;
    --output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --output-dir=*)
      OUTPUT_DIR="${1#*=}"
      shift
      ;;
    --version)
      require_value "$1" "${2:-}"
      VERSION="$2"
      shift 2
      ;;
    --version=*)
      VERSION="${1#*=}"
      shift
      ;;
    --commit)
      require_value "$1" "${2:-}"
      COMMIT="$2"
      shift 2
      ;;
    --commit=*)
      COMMIT="${1#*=}"
      shift
      ;;
    --agent-binary)
      require_value "$1" "${2:-}"
      AGENT_BINARY="$2"
      shift 2
      ;;
    --agent-binary=*)
      AGENT_BINARY="${1#*=}"
      shift
      ;;
    --filebeat-binary)
      require_value "$1" "${2:-}"
      FILEBEAT_BINARY="$2"
      shift 2
      ;;
    --filebeat-binary=*)
      FILEBEAT_BINARY="${1#*=}"
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
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

[[ -f "${SOURCE_ROOT}/go.mod" ]] || { echo "Elastic Agent source root not found: ${SOURCE_ROOT}" >&2; exit 1; }

if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -n 's/^const defaultBeatVersion = "\(.*\)"/\1/p' "${SOURCE_ROOT}/version/version.go" | head -n 1)"
fi
[[ -n "$VERSION" ]] || { echo "Cannot detect Elastic Agent version from version/version.go" >&2; exit 1; }

if [[ -z "$COMMIT" ]]; then
  COMMIT="$(git -c safe.directory="$SOURCE_ROOT" -C "$SOURCE_ROOT" rev-parse --short=12 HEAD 2>/dev/null || true)"
fi
[[ -n "$COMMIT" && "$COMMIT" != "unknown" && "$COMMIT" != "pqcdev" ]] || {
  echo "A real source commit is required. Run from a Git checkout or pass --commit explicitly." >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"
BUILD_DIR="${OUTPUT_DIR}/build/linux-amd64"
PACKAGE_ROOT="${OUTPUT_DIR}/package/ncs-elastic-agent-pqc-linux-amd64"
VERSIONED_HOME="data/elastic-agent-${VERSION}-${COMMIT}"
COMPONENTS_DIR="${PACKAGE_ROOT}/${VERSIONED_HOME}/components"
AGENT_OUT="${BUILD_DIR}/elastic-agent-pqc-linux-amd64"
FILEBEAT_OUT="${BUILD_DIR}/filebeat-pqc-linux-amd64"
PACKAGE_OUT="${OUTPUT_DIR}/ncs-elastic-agent-pqc-linux-amd64.tar.gz"
FILEBEAT_ZIP_OUT="${OUTPUT_DIR}/filebeat-pqc-linux-amd64.zip"
FILEBEAT_ARTIFACT_OUT="$FILEBEAT_ZIP_OUT"
SHA_OUT="${OUTPUT_DIR}/SHA256SUMS.txt"

echo "[INFO] Source root: ${SOURCE_ROOT}"
echo "[INFO] Output dir: ${OUTPUT_DIR}"
echo "[INFO] Version: ${VERSION}"
echo "[INFO] Commit/hash: ${COMMIT}"

if [[ "$SKIP_BUILD" != "1" ]]; then
  mkdir -p "$BUILD_DIR"
  echo "[1/4] Building custom Elastic Agent Linux binary"
  (cd "$SOURCE_ROOT" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags "-X github.com/elastic/elastic-agent/version.commit=${COMMIT}" \
    -o "$AGENT_OUT" .)

  echo "[2/4] Building custom Filebeat PQC Linux binary"
  (cd "${SOURCE_ROOT}/beats" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -o "$FILEBEAT_OUT" ./x-pack/filebeat)
else
  [[ -n "$AGENT_BINARY" && -f "$AGENT_BINARY" ]] || { echo "--skip-build requires --agent-binary" >&2; exit 1; }
  [[ -n "$FILEBEAT_BINARY" && -f "$FILEBEAT_BINARY" ]] || { echo "--skip-build requires --filebeat-binary" >&2; exit 1; }
  mkdir -p "$BUILD_DIR"
  [[ "$(readlink -f "$AGENT_BINARY")" == "$(readlink -f "$AGENT_OUT")" ]] || cp "$AGENT_BINARY" "$AGENT_OUT"
  [[ "$(readlink -f "$FILEBEAT_BINARY")" == "$(readlink -f "$FILEBEAT_OUT")" ]] || cp "$FILEBEAT_BINARY" "$FILEBEAT_OUT"
fi

echo "[3/4] Creating custom Agent package layout"
rm -rf "$PACKAGE_ROOT"
mkdir -p "$COMPONENTS_DIR"
cp "$AGENT_OUT" "${PACKAGE_ROOT}/elastic-agent"
cp "$AGENT_OUT" "${PACKAGE_ROOT}/${VERSIONED_HOME}/elastic-agent"
cp "$FILEBEAT_OUT" "${COMPONENTS_DIR}/testbeat"
chmod +x "${PACKAGE_ROOT}/elastic-agent" "${PACKAGE_ROOT}/${VERSIONED_HOME}/elastic-agent" "${COMPONENTS_DIR}/testbeat"

printf '%s\n' "$VERSION" > "${PACKAGE_ROOT}/package.version"
printf '%s\n' "$VERSION" > "${PACKAGE_ROOT}/${VERSIONED_HOME}/package.version"

cat > "${COMPONENTS_DIR}/testbeat.spec.yml" <<'YAML'
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

cat > "${PACKAGE_ROOT}/manifest.yaml" <<YAML
version: co.elastic.agent/v1
kind: PackageManifest
package:
  version: ${VERSION}
  snapshot: false
  hash: ${COMMIT}
  versioned-home: ${VERSIONED_HOME}
  flavors:
    basic:
      - testbeat
    servers:
      - testbeat
  path-mappings:
    - ${VERSIONED_HOME}: ${VERSIONED_HOME}
      manifest.yaml: ${VERSIONED_HOME}/manifest.yaml
YAML
cp "${PACKAGE_ROOT}/manifest.yaml" "${PACKAGE_ROOT}/${VERSIONED_HOME}/manifest.yaml"

echo "[4/4] Writing archives"
(cd "${OUTPUT_DIR}/package" && tar -czf "$PACKAGE_OUT" ncs-elastic-agent-pqc-linux-amd64)
rm -f "$FILEBEAT_ZIP_OUT"
if command -v zip >/dev/null 2>&1; then
  (cd "$BUILD_DIR" && zip -q "$FILEBEAT_ZIP_OUT" filebeat-pqc-linux-amd64)
else
  FILEBEAT_ARTIFACT_OUT="${OUTPUT_DIR}/filebeat-pqc-linux-amd64.tar.gz"
  tar -czf "$FILEBEAT_ARTIFACT_OUT" -C "$BUILD_DIR" filebeat-pqc-linux-amd64
fi

{
  sha256sum "$PACKAGE_OUT"
  if [[ -f "$FILEBEAT_ZIP_OUT" ]]; then
    sha256sum "$FILEBEAT_ZIP_OUT"
  else
    sha256sum "$FILEBEAT_ARTIFACT_OUT"
  fi
} > "$SHA_OUT"

echo "[OK] Package: ${PACKAGE_OUT}"
echo "[OK] Filebeat artifact: ${FILEBEAT_ARTIFACT_OUT}"
echo "[OK] SHA256: ${SHA_OUT}"
