# Phase 1C Fleet-managed PQC Test

## Prerequisites

- PQC Gateway listening on `192.168.22.171:5443`.
- Gateway forwards raw Beats/Lumberjack bytes to Logstash `127.0.0.1:5044`.
- Logstash outputs to Elasticsearch.
- Kibana/Fleet Server is reachable at `https://192.168.22.171:5601` and `https://192.168.22.171:8220`.
- Windows test machine runs an elevated Administrator PowerShell.
- Custom binaries are available:
  - extracted Phase 1C Agent package containing `elastic-agent.exe`
  - `filebeat-pqc-windows-amd64.exe`

The Phase 1C install script can also accept a renamed Agent binary such as `elastic-agent-pqc-phase1c-windows-amd64.exe`. It will copy it to the canonical `elastic-agent.exe` package name and create the minimal package files required by `elastic-agent install`.

## Fleet Policy

Create or edit a Fleet policy for this test.

Recommended first integration:

- Integration: Custom logs
- Path: `C:\pqc-test\fleet-pqc-test.log`
- Dataset/name: any lab value, for example `phase1_pqc_fleet`

Policy output:

- Type: Logstash
- Host: `192.168.22.171:5443`
- SSL enabled
- Lab verification: `verification_mode: none`

Advanced YAML if Fleet allows it:

```yaml
ssl.enabled: true
ssl.verification_mode: none
ssl.curve_types: ["X25519MLKEM768"]
ssl.supported_protocols: ["TLSv1.3"]
ssl.strict_pqc: true
```

If Fleet rejects `ssl.curve_types` or `ssl.strict_pqc`, keep the output as basic TLS Logstash and use the env fallback from the install script.

## Enrollment Token

In Kibana:

```text
Fleet -> Enrollment tokens -> create/copy token for the Phase 1C policy
```

Do not paste the token into docs or logs.

## Windows Install / Enroll

Run from elevated Administrator PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\pqc-test\install-agent-fleet-pqc-windows.ps1 `
  -ElasticAgentExe "C:\pqc-phase1c\elastic-agent.exe" `
  -FilebeatPqcExe "C:\pqc\filebeat-pqc-windows-amd64.exe" `
  -FleetUrl "https://192.168.22.171:8220" `
  -EnrollmentToken "<PASTE_TOKEN_HERE>" `
  -Insecure
```

The script:

- prepares the local Agent package layout for `elastic-agent install`
- creates `manifest.yaml`, `package.version`, and `data\elastic-agent-<version>-<commit>`
- places a `testbeat.exe` placeholder and `testbeat.spec.yml` into the package component directory
- creates `C:\pqc-test\fleet-pqc-test.log`
- writes bootstrap lines larger than 1024 bytes
- sets Machine-level PQC env
- sets current process PQC env
- runs `elastic-agent install --force --non-interactive --url=... --enrollment-token=...`
- prints commands to inspect Filebeat child process

## Check Windows Agent

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\pqc-test\check-agent-fleet-pqc-windows.ps1
```

Manual process check:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -like "*filebeat*" -or $_.CommandLine -like "*filebeat*" } |
  Select-Object ProcessId,CommandLine
```

Expected:

- Elastic Agent service is running.
- Filebeat child process command line points to `filebeat-pqc-windows-amd64.exe`, or Agent log shows `using_custom_filebeat=true`.
- Machine env contains `PQC_FILEBEAT_BIN` and the three `LOGSTASH_TLS_*` values.

Append another event:

```powershell
Add-Content C:\pqc-test\fleet-pqc-test.log "fleet-pqc-event $(Get-Date -Format o)"
```

## Check Kibana Fleet

In Kibana:

```text
Fleet -> Agents
```

Expected:

- Agent appears Online/Healthy.
- Agent is assigned to the intended Phase 1C policy.
- Policy output is Logstash pointing to `192.168.22.171:5443`.

## Check Agent / Filebeat Logs

Common Windows paths:

```text
C:\Program Files\Elastic\Agent\data\elastic-agent-*\logs
```

Expected Agent log:

```text
using_custom_filebeat=true
component=filebeat
fleet_managed=true
child_env_pqc_enabled=true
pqc_env_forwarded=true
policy_output=logstash
logstash_hosts=[192.168.22.171:5443]
```

Expected Filebeat child log:

```text
pqc_mode=enabled
tls_min_version=TLSv1.3
tls_max_version=TLSv1.3
curve_preferences=[X25519MLKEM768]
strict_pqc=true
```

## Check Ubuntu Gateway

Gateway log should show:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes=...
```

The gateway does not decode events. It only proves TLS termination and raw stream forwarding.

## Check Logstash

Logstash stdout or logs should show an event from:

```text
C:\pqc-test\fleet-pqc-test.log
```

If Logstash writes to a PQC index, confirm the output index is receiving documents.

## Check Elasticsearch

Example:

```bash
curl -k -u elastic:<PASSWORD> "https://localhost:9200/_cat/indices/*pqc*?v"
```

Look for the Phase 1 PQC index, for example:

```text
phase1-pqc-filebeat-*
```

## Check Kibana Discover

Use data view:

```text
phase1-pqc-filebeat
```

Search:

```text
message : "fleet-pqc-event*"
```

or:

```text
log.file.path : "C:\\pqc-test\\fleet-pqc-test.log"
```

## Rollback / Cleanup

Uninstall Agent from elevated PowerShell:

```powershell
elastic-agent uninstall --force
```

If the command is not in PATH, run the installed binary:

```powershell
& "C:\Program Files\Elastic\Agent\elastic-agent.exe" uninstall --force
```

Remove Machine-level env:

```powershell
[Environment]::SetEnvironmentVariable("PQC_FILEBEAT_BIN", $null, "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_CURVE_TYPES", $null, "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_MIN_VERSION", $null, "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_STRICT_PQC", $null, "Machine")
```

Remove test data if needed:

```powershell
Remove-Item C:\pqc-test -Recurse -Force
```

Install official Elastic Agent again when returning to normal behavior.

## PASS Criteria

- `elastic-agent-pqc.exe install/enroll` succeeds.
- Agent appears Online/Healthy in Kibana Fleet.
- Agent receives policy with Logstash output to `192.168.22.171:5443`.
- Agent spawns `filebeat-pqc-windows-amd64.exe`.
- Agent log shows `using_custom_filebeat=true`.
- Filebeat child logs PQC mode enabled.
- Gateway shows TLS 1.3 handshake and bytes forwarded to Logstash.
- Logstash receives event from `fleet-pqc-test.log`.
- Elasticsearch has the event.
- Kibana Discover shows the event from Windows.
- Agent uninstall succeeds.
- Without `PQC_FILEBEAT_BIN`, Agent uses default behavior.
