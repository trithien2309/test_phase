# Phase 1B Elastic Agent Standalone PQC

## Goal

Phase 1B validates the process runtime path where Elastic Agent runs standalone, resolves a Filebeat component, and spawns the custom PQC-enabled Filebeat binary instead of the default Filebeat binary.

Target flow:

```text
elastic-agent-pqc.exe
  -> filebeat-pqc-windows-amd64.exe
  -> output.logstash 192.168.22.171:5443
  -> PQC Gateway
  -> Logstash :5044
  -> Elasticsearch / Kibana
```

## Component Spawn Path Found

Elastic Agent resolves and runs Filebeat through this path:

1. `internal/pkg/agent/application/application.go`
   Loads component specs with `component.LoadRuntimeSpecs(paths.Components(), platform)`.

2. `pkg/component/load.go`
   Maps input specs to `InputRuntimeSpec`, including `BinaryName`, `BinaryPath`, and the command name from the spec.

3. `pkg/component/component.go`
   `Component.BinaryName()` returns the runtime command name. In the dev `testbeat.spec.yml`, the binary on disk can be `testbeat`, but the command name is `filebeat`.

4. `pkg/component/runtime/manager.go`
   Creates runtime instances for the component model.

5. `pkg/component/runtime/command.go`
   `commandRuntime.start()` builds env, args, workdir, and calls `process.Start(path, ...)`.

6. `pkg/core/process/process.go`
   Starts the child process using `exec.Cmd`.

The Phase 1B patch is placed in `pkg/component/runtime`, because that is the layer that still knows the component command name while preserving the existing process lifecycle.

## PQC_FILEBEAT_BIN Override

Set:

```powershell
$env:PQC_FILEBEAT_BIN="C:\path\to\filebeat-pqc-windows-amd64.exe"
```

When `commandRuntime.start()` is about to spawn a command component:

- if the component command name is `filebeat`
- and `PQC_FILEBEAT_BIN` is set
- and the target exists and is a file

Agent uses `PQC_FILEBEAT_BIN` as the process path.

The original args, env, stdout, stderr, working directory, monitoring enrichment, check-in lifecycle, and stop/restart lifecycle are unchanged.

If `PQC_FILEBEAT_BIN` is unset, the default Agent behavior is unchanged. Non-Filebeat components are ignored.

## PQC Environment

The child process inherits the parent environment. The patch also explicitly propagates these env vars into the component env list when present:

```text
LOGSTASH_TLS_CURVE_TYPES=X25519MLKEM768
LOGSTASH_TLS_MIN_VERSION=1.3
LOGSTASH_TLS_STRICT_PQC=true
```

These env vars are the fallback path if the standalone policy path does not pass `ssl.curve_types` or `ssl.strict_pqc` cleanly into the Filebeat Logstash output.

## Expected Agent Log

When the override is active, Agent logs:

```text
Using custom Filebeat binary from PQC_FILEBEAT_BIN
using_custom_filebeat=true
component=filebeat
custom_filebeat_path=...
original_filebeat_path=...
```

Expected child Filebeat logs:

```text
Logstash PQC TLS mode configured
pqc_mode=enabled
tls_min_version=TLSv1.3
tls_max_version=TLSv1.3
curve_preferences=[X25519MLKEM768]
strict_pqc=true
TLS handshake completed
```

## Standalone Config

Use:

```text
tools/pqc-test/elastic-agent-standalone-pqc.yml
```

The Windows helper script also prepares the minimal standalone component layout that Agent needs before it can resolve a Filebeat component:

```text
<agent-dir>/package.version
<agent-dir>/data/elastic-agent-9.5.0-unknown/components/testbeat.spec.yml
<agent-dir>/data/elastic-agent-9.5.0-unknown/components/testbeat.exe
```

`testbeat.spec.yml` is the development spec that maps `filestream` to command name `filebeat`. `testbeat.exe` only satisfies Agent's spec/binary existence check; `PQC_FILEBEAT_BIN` is still the binary path used when the Filebeat command is spawned.

The config reads:

```text
C:/pqc-test/agent-standalone-*.log
```

and sends to:

```text
192.168.22.171:5443
```

The config uses standalone Agent format:

```yaml
outputs:
  default:
    type: logstash
    hosts: ["192.168.22.171:5443"]
```

This is the Agent equivalent of Beats `output.logstash`.

## Windows Test

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\pqc-test\run-agent-standalone-pqc-windows.ps1
```

Or explicitly:

```powershell
$env:AGENT_BIN="C:\path\to\elastic-agent-pqc.exe"
$env:PQC_FILEBEAT_BIN="C:\path\to\filebeat-pqc-windows-amd64.exe"
$env:LOGSTASH_TLS_CURVE_TYPES="X25519MLKEM768"
$env:LOGSTASH_TLS_MIN_VERSION="1.3"
$env:LOGSTASH_TLS_STRICT_PQC="true"

.\elastic-agent-pqc.exe run -c .\tools\pqc-test\elastic-agent-standalone-pqc.yml -e
```

Check the child process:

```powershell
Get-CimInstance Win32_Process | Where-Object {$_.Name -like "*filebeat*"} | Select ProcessId,CommandLine
```

Append more test data while Agent is running:

```powershell
$Padding = "A" * 1600
Add-Content C:\pqc-test\agent-standalone-phase1b.log "phase1b-manual-event $(Get-Date -Format o) $Padding"
```

## PASS Checklist

- `elastic-agent-pqc.exe` starts in standalone mode.
- Agent logs `using_custom_filebeat=true`.
- Child process command line points to `filebeat-pqc-windows-amd64.exe`.
- Child Filebeat logs `pqc_mode=enabled`.
- Child Filebeat logs `curve_preferences=[X25519MLKEM768]`.
- PQC Gateway logs `handshake ok tls_version=TLS 1.3`.
- PQC Gateway logs forward bytes to `127.0.0.1:5044`.
- Logstash receives the event.
- Elasticsearch receives an index such as `phase1-pqc-agent-standalone-*` or `phase1-pqc-filebeat-*`.
- Kibana Discover shows logs from the Windows host and `C:\pqc-test\agent-standalone-phase1b.log`.

## Known Limitations

- This is a PoC override for standalone testing. It does not replace the production Fleet artifact resolver yet.
- Agent still needs a normal Elastic Agent component layout and spec files. `PQC_FILEBEAT_BIN` only overrides the binary that is spawned after the Filebeat component has been resolved.
- The included Windows script prepares a minimal `testbeat` component layout for this standalone PoC. Production packaging should use real signed component artifacts.
- Client-side Go TLS does not expose the negotiated named group. Prove selected group with the gateway or packet capture.
- The sample config uses `ssl.verification_mode: none` for lab convenience. Production should use CA validation and correct SANs.

## Next Step for Fleet-Managed

Phase 2 should move this from env-based PoC override to a proper Fleet-managed artifact path:

- publish custom Filebeat component artifact
- make the Agent artifact manifest resolve the custom component
- keep the PQC TLS config in Beats/libbeat
- validate policy-delivered Logstash output through Fleet
