# NCS Elastic Agent PQC Installer

This folder contains Windows installer flows for the custom Elastic Agent + PQC Filebeat PoC.

Use `elastic-agent-ncs-standalone-install.ps1` when you do not want Fleet Server. Use `elastic-agent-ncs-install.ps1` only for Fleet-managed testing.

## What It Does

`elastic-agent-ncs-standalone-install.ps1`:

- removes an existing Elastic Agent service/install
- downloads or uses local Phase 1C artifacts
- extracts `elastic-agent-pqc` and `filebeat-pqc`
- prepares the minimal Elastic Agent package layout required by `elastic-agent install`
- writes a local standalone `elastic-agent.yml`
- sets Machine-level PQC env for the Windows service
- verifies Windows audit/GPO settings in read-only mode
- installs Elastic Agent as a standalone service without Fleet URL/token
- prints local and server-side verification commands

`elastic-agent-ncs-install.ps1`:

- removes an existing Elastic Agent service/install
- downloads or uses local Phase 1C artifacts
- extracts `elastic-agent-pqc` and `filebeat-pqc`
- prepares the minimal Elastic Agent package layout required by `elastic-agent install`
- sets Machine-level PQC env for the Windows service
- verifies Windows audit/GPO settings in read-only mode
- installs/enrolls Elastic Agent into Fleet
- prints local and server-side verification commands

It does not install Suricata, Npcap, Sysmon, firewall blockers, or scheduled response tasks.

## Standalone Install, No Fleet

Run from elevated Administrator PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ncs\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443
```

Use local artifacts instead of downloading:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ncs\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443 `
  -AgentPackageZip "C:\path\elastic-agent-pqc-phase1c-windows-amd64-package.zip" `
  -FilebeatPqcZip "C:\path\filebeat-pqc-windows-amd64.zip"
```

The standalone config reads:

```text
Security
Windows PowerShell
Microsoft-Windows-PowerShell/Operational
C:\pqc-test\ncs-agent-smoke.log
```

The smoke file is only for quick transport verification. Windows Event Logs are the primary source.

## Fleet Policy Required First For Fleet Mode

Create a Fleet policy named for example `ncs-windows-pqc`.

Output:

```text
Type: Logstash
Host: 192.168.22.171:5443
SSL enabled
verification_mode: none for lab
```

Advanced YAML if Fleet accepts it:

```yaml
ssl.enabled: true
ssl.verification_mode: none
ssl.curve_types: ["X25519MLKEM768"]
ssl.supported_protocols: ["TLSv1.3"]
ssl.strict_pqc: true
```

Windows log integrations for v1:

```text
Security
Windows PowerShell
Microsoft-Windows-PowerShell/Operational
```

## Run

Run from elevated Administrator PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ncs\elastic-agent-ncs-install.ps1 `
  -FleetUrl "https://192.168.22.171:8220" `
  -EnrollmentToken "<TOKEN>" `
  -Insecure
```

Use local artifacts instead of downloading:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ncs\elastic-agent-ncs-install.ps1 `
  -FleetUrl "https://192.168.22.171:8220" `
  -EnrollmentToken "<TOKEN>" `
  -AgentPackageZip "C:\path\elastic-agent-pqc-phase1c-windows-amd64-package.zip" `
  -FilebeatPqcZip "C:\path\filebeat-pqc-windows-amd64.zip" `
  -Insecure
```

## Expected Markers

Agent/Filebeat logs:

```text
using_custom_filebeat=true
fleet_managed=true
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
