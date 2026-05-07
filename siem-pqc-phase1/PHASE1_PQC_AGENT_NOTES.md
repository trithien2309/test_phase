# Phase 1 PQC Agent Notes

## Scope

Phase 1 patches the client side of the Logstash output path so a custom Beat or Fleet-managed Elastic Agent can prefer or force TLS 1.3 with the PQC named group `X25519MLKEM768` when sending Lumberjack traffic to a PQC gateway.

## Why the patch is in Beats/libbeat

The actual Logstash client connection is created in Beats, not in the Elastic Agent supervisor:

- `beats/libbeat/outputs/logstash/logstash.go`
- `beats/libbeat/outputs/logstash/config.go`
- `elastic-agent-libs/transport/tlscommon/*`
- `elastic-agent-libs/transport/tls.go`

Elastic Agent root confirmed this wiring:

- `elastic-agent/go.mod` uses `replace github.com/elastic/beats/v7 => ./beats`
- `.gitmodules` defines `beats` as the official `elastic/beats` submodule
- `magefile.go` imports Beats build logic directly

Decision: patch the Logstash output and the shared TLS parsing layer used by Beats, then keep Elastic Agent pointed at the patched local sources.

## Important code path

1. `beats/libbeat/outputs/logstash/readConfig(...)`
   Parses `output.logstash.*`, including `ssl.*`.
2. `beats/libbeat/outputs/logstash/MakeLogstashClients(...)`
   Reads hosts, prepares TLS, and creates one transport client per Logstash host.
3. `elastic-agent-libs/transport/tlscommon.LoadTLSConfig(...)`
   Turns YAML or Fleet policy TLS config into internal TLS settings.
4. `elastic-agent-libs/transport/tlscommon.(*TLSConfig).BuildModuleClientConfig(...)`
   Produces the final Go `tls.Config`.
5. `elastic-agent-libs/transport/tls.go`
   Performs the client TLS handshake used by Logstash output transport.

## What changed

### Beats Logstash output

- Added `beats/libbeat/outputs/logstash/pqc.go`
- Supports env override:
  - `LOGSTASH_TLS_CURVE_TYPES`
  - `LOGSTASH_TLS_MIN_VERSION`
  - `LOGSTASH_TLS_STRICT_PQC`
- When PQC is enabled:
  - forces `supported_protocols` to `TLSv1.3`
  - strict mode forces `curve_types` to `[X25519MLKEM768]`
  - preferred mode uses `[X25519MLKEM768, X25519]`
- Emits config log showing:
  - `pqc_mode=enabled`
  - `tls_min_version`
  - `tls_max_version`
  - `curve_preferences`
  - `strict_pqc`
  - `logstash_hosts`

### Shared TLS layer

- Added `ssl.strict_pqc` to the shared TLS config surface.
- Added curve parsing support for `X25519MLKEM768`.
- Added post-handshake debug logging with:
  - `tls_version`
  - `cipher_suite`
  - `server_name`
  - `configured_curve_preferences`
  - leaf cert subject and SHA-256 fingerprint when available
  - `selected_group_proof_required_from_gateway_or_pcap=true`

### Elastic Agent translate path

- Added `X25519MLKEM768` mapping in `internal/pkg/otel/translate/common.go`.
- Updated translate tests to accept the new optional `strict_pqc` field in raw TLS config maps.

## Build wiring

To keep the patch in-workspace and reproducible:

- `elastic-agent/go.mod` now replaces:
  - `github.com/elastic/beats/v7 => ./beats`
  - `github.com/elastic/elastic-agent-libs => ./elastic-agent-libs`
- `beats/go.mod` now replaces:
  - `github.com/elastic/elastic-agent-libs => ../elastic-agent-libs`

This means:

- building from the Elastic Agent root uses patched Beats and patched agent libs
- building Filebeat from `beats/` also uses the same patched TLS layer

## Phase 1 enforcement behavior

### Disabled

If PQC is not enabled by config or env:

- existing Logstash output behavior is preserved
- no TLS version or curve forcing is applied

### Preferred PQC

Enabled by:

- `ssl.curve_types: ["X25519MLKEM768"]`
- or `LOGSTASH_TLS_CURVE_TYPES=X25519MLKEM768`
- while `strict_pqc` is false

Behavior:

- TLS 1.3 only
- curve preferences become `[X25519MLKEM768, X25519]`

### Strict PQC

Enabled by:

- `ssl.strict_pqc: true`
- or `LOGSTASH_TLS_STRICT_PQC=true`

Behavior:

- TLS 1.3 only
- curve preferences become `[X25519MLKEM768]`
- no classical fallback

## Evidence limits

Go `crypto/tls` does not expose the negotiated named group in `ConnectionState`, so the client logs only the configured preference list.

Proof of selected group must come from:

- PQC Gateway logs
- OpenSSL or BoringSSL handshake logs on the gateway
- packet capture

