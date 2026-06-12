# Tested Windows Standalone PQC Flow

## Status

The Windows standalone flow passed end-to-end validation in the lab.

## Client Runtime

The installer configures these machine-level variables:

```text
PQC_FILEBEAT_BIN=C:\ncs-elastic-agent-standalone\filebeat\filebeat-pqc-windows-amd64.exe
LOGSTASH_TLS_CURVE_TYPES=X25519MLKEM768
LOGSTASH_TLS_MIN_VERSION=1.3
LOGSTASH_TLS_STRICT_PQC=true
```

The custom Elastic Agent Windows service spawns:

```text
filebeat-pqc-windows-amd64.exe
```

Collected sources:

```text
Windows Security
Windows PowerShell
Microsoft-Windows-PowerShell/Operational
C:\pqc-test\ncs-agent-smoke.log
```

## Client Proof

Observed Filebeat log fields:

```text
message: TLS handshake completed
component.binary: filebeat
log.logger: logstash.tls
tls_version: TLS 1.3
cipher_suite: TLS_AES_128_GCM_SHA256
server_name: 192.168.22.171
configured_curve_preferences: ["X25519MLKEM768"]
selected_group_proof_required_from_gateway_or_pcap: true
```

## Gateway Proof

Observed Gateway log fields:

```text
handshake ok remote=192.168.22.172 tls_version=TLS 1.3 cipher=TLS_AES_128_GCM_SHA256
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes=...
```

## Kibana Proof

Observed in Kibana Discover:

```text
Data view: phase1-pqc-filebeat
host.name: THIEN-WIN-SRV
winlog.channel: Microsoft-Windows-PowerShell/Operational
winlog.event_data.ScriptBlockText: whoami
Windows Security Process Creation events
```

## PQC Proof Boundary

The client and Gateway restrict the configured curve preference to `X25519MLKEM768`. Go `crypto/tls` does not expose the negotiated named group through `ConnectionState`, so the log intentionally does not claim a selected group.

For cryptographic proof of the negotiated group, capture traffic on Gateway port `5443` and inspect the TLS key share:

```bash
sudo tcpdump -i any host 192.168.22.172 and port 5443 -w /tmp/pqc-agent-5443.pcap
```

Expected group:

```text
X25519MLKEM768
0x11ec
4588
```

## Current Limitations

```text
Windows standalone only
No Fleet-managed dynamic policy
No Linux/macOS installer yet
GPO/audit verification is read-only
Lab TLS verification_mode is none
Production certificate validation and signing remain required
```

