# Phase 1 PQC Agent Test

## Test target

Client -> PQC Gateway `192.168.22.171:5443` -> raw Lumberjack passthrough -> Logstash `127.0.0.1:5044` or `192.168.22.171:5044`

Success criteria:

- client uses TLS 1.3
- client configures `X25519MLKEM768`
- gateway proves selected group is `X25519MLKEM768`
- Logstash still receives normal Beats payload

## Proof model

The custom client can prove:

- PQC mode enabled
- TLS min and max version forced to `TLSv1.3`
- configured curve preferences are `X25519MLKEM768` or `X25519MLKEM768,X25519`
- TLS handshake succeeded

The gateway or packet capture must prove:

- negotiated TLS version is `TLSv1.3`
- selected group is `X25519MLKEM768`

## Path 1: Quick proof with custom Filebeat

### Example config

Use `tools/pqc-test/example-filebeat-pqc.yml`

Key fields:

```yaml
filebeat.inputs:
  - type: filestream
    id: pqc-test-log
    enabled: true
    paths:
      - /tmp/pqc-test.log

output.logstash:
  hosts: ["192.168.22.171:5443"]
  ssl.enabled: true
  ssl.certificate_authorities: ["/path/to/ca.crt"]
  ssl.curve_types: ["X25519MLKEM768"]
  ssl.supported_protocols: ["TLSv1.3"]
  ssl.strict_pqc: true
```

### Linux run

```bash
cd /path/to/elastic-agent
chmod +x build/filebeat-pqc-linux-amd64
chmod +x tools/pqc-test/run-filebeat-pqc-linux.sh
./tools/pqc-test/run-filebeat-pqc-linux.sh
```

### Windows run

```powershell
cd C:\Users\trith\Desktop\SIEM\elastic-agent
powershell -ExecutionPolicy Bypass -File .\tools\pqc-test\run-filebeat-pqc-windows.ps1
```

### What to verify in logs

Expected client-side lines:

- `Logstash PQC TLS mode configured`
- `pqc_mode=enabled`
- `tls_min_version=TLSv1.3`
- `tls_max_version=TLSv1.3`
- `curve_preferences=[X25519MLKEM768]`
- `strict_pqc=true`
- `selected_group_proof_required_from_gateway_or_pcap=true`
- `TLS handshake completed`

### Gateway-side proof

Collect one of:

- gateway TLS debug logs
- OpenSSL or BoringSSL server logs
- `tcpdump` or `wireshark` capture on `5443`

Required proof items:

- negotiated protocol is `TLSv1.3`
- selected group is `X25519MLKEM768`

### Backend proof

Verify Logstash receives events normally from the gateway-forwarded connection.

Examples:

- Logstash beats input receives documents
- Elasticsearch index receives the Filebeat test line
- no payload format changes are needed

## Path 2: Fleet-managed Elastic Agent

### Target flow

1. Install custom Elastic Agent binary from this patched source tree.
2. Enroll it into Fleet as normal.
3. Keep integrations Fleet-managed.
4. Point the Logstash output host to `192.168.22.171:5443`.

### Fleet policy settings

Preferred future policy fields:

```yaml
output.logstash:
  hosts: ["192.168.22.171:5443"]
  ssl.enabled: true
  ssl.certificate_authorities: ["/path/to/ca.crt"]
  ssl.curve_types: ["X25519MLKEM768"]
  ssl.supported_protocols: ["TLSv1.3"]
  ssl.strict_pqc: true
```

### Phase 1 fallback using environment variables

If the Fleet UI or generated output policy does not expose PQC fields yet, run the Agent with:

```text
LOGSTASH_TLS_CURVE_TYPES=X25519MLKEM768
LOGSTASH_TLS_MIN_VERSION=1.3
LOGSTASH_TLS_STRICT_PQC=true
```

These env vars are consumed by the patched Logstash output path in Beats.

### Suggested debug

Run with debug selectors that include:

- `logstash`
- `tls`
- `pqc`

Examples:

```text
-d logstash,tls,pqc
```

### Fleet-managed limitation in Phase 1

This patch proves the client-side Logstash path and keeps the Fleet-managed architecture intact, but it does not yet ship a fully repackaged Agent distribution with all custom components bundled for production rollout.

## Suggested gateway checks

- TLS listener only accepts TLS 1.3
- gateway logs negotiated group
- gateway forwards raw bytes to Logstash `5044`
- Logstash still decodes Lumberjack frames unchanged

## Negative tests

### Strict mode should fail if gateway does not support `X25519MLKEM768`

- keep `ssl.strict_pqc: true`
- point to a non-PQC TLS server
- expected result: handshake failure

### Disabled PQC should preserve legacy behavior

- remove env vars
- remove `ssl.curve_types`
- remove `ssl.strict_pqc`
- expected result: default Logstash TLS behavior returns

