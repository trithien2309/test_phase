# NCS Standalone PQC Elastic Agent

This folder is the no-Fleet test path for the custom SIEM ELK project.

The Windows installer installs Elastic Agent in standalone mode, writes local config, spawns the custom PQC Filebeat, and sends logs to the PQC Gateway.

## Flow

```text
Windows client
  -> elastic-agent-ncs-standalone-install.ps1
  -> Elastic Agent standalone service
  -> filebeat-pqc-windows-amd64.exe
  -> TLS 1.3 + X25519MLKEM768
  -> PQC Gateway 192.168.22.171:5443
  -> raw Beats/Lumberjack
  -> Logstash :5044
  -> Elasticsearch / Kibana
```

## Windows Quick Test

Run PowerShell as Administrator:

```powershell
cd C:\test_phase\ncs-standalone-pqc

powershell -ExecutionPolicy Bypass -File .\tools\ncs\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443
```

The script downloads these existing artifacts automatically:

```text
https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages/elastic-agent-pqc-phase1c-windows-amd64-package.zip
https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages/filebeat-pqc-windows-amd64.zip
```

If you already have the zip files locally:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ncs\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443 `
  -AgentPackageZip "C:\path\elastic-agent-pqc-phase1c-windows-amd64-package.zip" `
  -FilebeatPqcZip "C:\path\filebeat-pqc-windows-amd64.zip"
```

## Sources Collected

Standalone config reads:

```text
Security
Windows PowerShell
Microsoft-Windows-PowerShell/Operational
C:\pqc-test\ncs-agent-smoke.log
```

The smoke file is only for quick transport verification. The real Windows log sources are the event logs above.

## Expected Markers

Windows Agent/Filebeat logs:

```text
using_custom_filebeat=true
pqc_env_forwarded=true
pqc_mode=enabled
curve_preferences=[X25519MLKEM768]
strict_pqc=true
```

Gateway logs:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes=...
```

Kibana:

```text
Data view: ncs-windows-pqc-*
Search: data_stream.dataset : "ncs.transport_smoke"
Search: event.code : "4688" or event.code : "4104"
```
