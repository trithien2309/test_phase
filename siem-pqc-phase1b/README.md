# SIEM PQC Phase 1B

Phase 1B tests Elastic Agent standalone spawning the custom PQC Filebeat component.

Flow:

```text
elastic-agent-pqc-phase1b-windows-amd64.exe
  -> filebeat-pqc-windows-amd64.exe via PQC_FILEBEAT_BIN
  -> 192.168.22.171:5443
  -> PQC Gateway
  -> Logstash :5044
  -> Elasticsearch / Kibana
```

## Files

- `elastic-agent-pqc-phase1b-windows-amd64.zip`: Elastic Agent binary with `PQC_FILEBEAT_BIN` override.
- `filebeat-pqc-windows-amd64.zip`: PQC-enabled Filebeat binary from Phase 1A.
- `PHASE1B_AGENT_STANDALONE_PQC.md`: implementation notes and pass checklist.
- `components/testbeat.spec.yml`: minimal Agent component spec for resolving `filestream -> filebeat`.
- `tools/pqc-test/elastic-agent-standalone-pqc.yml`: standalone Agent config.
- `tools/pqc-test/run-agent-standalone-pqc-windows.ps1`: Windows test runner.

## Quick Test

```powershell
cd .\siem-pqc-phase1b
Expand-Archive .\elastic-agent-pqc-phase1b-windows-amd64.zip -DestinationPath .\agent -Force
Expand-Archive .\filebeat-pqc-windows-amd64.zip -DestinationPath .\filebeat -Force

$env:AGENT_BIN="$PWD\agent\elastic-agent-pqc-phase1b-windows-amd64.exe"
$env:PQC_FILEBEAT_BIN="$PWD\filebeat\filebeat-pqc-windows-amd64.exe"

powershell -ExecutionPolicy Bypass -File .\tools\pqc-test\run-agent-standalone-pqc-windows.ps1
```

The script prepares the local Agent component directory automatically before running Agent.

Check the spawned child:

```powershell
Get-CimInstance Win32_Process | Where-Object {$_.Name -like "*filebeat*"} | Select ProcessId,CommandLine
```

Expected Agent log contains:

```text
using_custom_filebeat=true
component=filebeat
```

Expected Filebeat child log contains:

```text
pqc_mode=enabled
curve_preferences=[X25519MLKEM768]
strict_pqc=true
```
