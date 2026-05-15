# SIEM PQC Phase 1C - Fleet-managed Elastic Agent

Phase 1C tests Elastic Agent in Fleet-managed mode while forcing the spawned Filebeat component to use the custom PQC Filebeat binary.

## Artifacts

- `packages/elastic-agent-pqc-phase1c-windows-amd64-package.zip`
  - Contains `elastic-agent.exe`, component spec, docs, and helper scripts.
  - SHA256: `6F60284463EFA4CA835A946AB156A10D865F8D5BB226445AF0AA97CBED6F4093`
- `packages/filebeat-pqc-windows-amd64.zip`
  - Contains `filebeat-pqc-windows-amd64.exe`.
  - SHA256: `81DEE76CC5CAB9CB0D7E5E0F24EFB20CFE8634485DB206521752D6B4A6E286FE`

## Quick Test

Run from elevated Administrator PowerShell after creating a Fleet policy with Logstash output `192.168.22.171:5443`.

```powershell
Expand-Archive .\packages\elastic-agent-pqc-phase1c-windows-amd64-package.zip C:\pqc-phase1c-agent -Force
Expand-Archive .\packages\filebeat-pqc-windows-amd64.zip C:\pqc-phase1c-filebeat -Force

powershell -ExecutionPolicy Bypass -File C:\pqc-phase1c-agent\tools\pqc-test\install-agent-fleet-pqc-windows.ps1 `
  -ElasticAgentExe "C:\pqc-phase1c-agent\elastic-agent.exe" `
  -FilebeatPqcExe "C:\pqc-phase1c-filebeat\filebeat-pqc-windows-amd64.exe" `
  -FleetUrl "https://192.168.22.171:8220" `
  -EnrollmentToken "<PASTE_TOKEN_HERE>" `
  -Insecure
```

Check:

```powershell
powershell -ExecutionPolicy Bypass -File C:\pqc-phase1c-agent\tools\pqc-test\check-agent-fleet-pqc-windows.ps1
Add-Content C:\pqc-test\fleet-pqc-test.log "fleet-pqc-event $(Get-Date -Format o)"
```

Expected Agent log markers:

```text
using_custom_filebeat=true
fleet_managed=true
component=filebeat
pqc_env_forwarded=true
policy_output=logstash
logstash_hosts=[192.168.22.171:5443]
```

Expected Gateway markers:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes=...
```

Full instructions are in:

- `docs/PHASE1C_AGENT_FLEET_PQC.md`
- `docs/PHASE1C_AGENT_FLEET_PQC_TEST.md`
