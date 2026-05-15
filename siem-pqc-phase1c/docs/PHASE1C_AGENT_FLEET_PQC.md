# Phase 1C Fleet-managed Elastic Agent PQC

## Goal

Phase 1C moves from standalone Agent testing to Fleet-managed testing:

```text
elastic-agent-pqc.exe install/enroll
  -> Fleet Server https://192.168.22.171:8220
  -> Fleet policy with Logstash output 192.168.22.171:5443
  -> Agent process runtime
  -> filebeat-pqc-windows-amd64.exe
  -> TLS 1.3 + X25519MLKEM768
  -> PQC Gateway :5443
  -> Logstash :5044
  -> Elasticsearch / Kibana
```

## Fleet-managed Flow Found

Install and enroll:

- `internal/pkg/agent/cmd/install.go`
  - `newInstallCommandWithArgs` defines `elastic-agent install`.
  - `installCmd` validates flags, installs the service, starts it, then runs `elastic-agent enroll --from-install`.
- `internal/pkg/agent/cmd/enroll.go`
  - handles Fleet URL, enrollment token, `--insecure`, and local Fleet-managed config.
- `internal/pkg/agent/cmd/enroll_cmd.go`
  - performs the Fleet enrollment request and persists resulting Fleet config.

Receiving policy from Fleet:

- `internal/pkg/agent/application/managed_mode.go`
  - runs the Fleet gateway and handles managed-mode communication.
- `internal/pkg/agent/application/actions/handlers/handler_action_policy_change.go`
  - handles policy change actions and validates Fleet connectivity changes.
- `internal/pkg/agent/application/coordinator/coordinator.go`
  - applies config changes, generates the component model, and updates runtime managers.

Creating component runtime:

- `internal/pkg/agent/application/application.go`
  - loads component specs with `component.LoadRuntimeSpecs(paths.Components(), platform)`.
  - creates the process runtime manager with `runtime.NewManager`.
- `pkg/component/component.go`
  - converts policy into components and units.
  - tracks `OutputType`, `OutputName`, input units, and output units.
- `pkg/component/load.go`
  - maps spec files to `InputRuntimeSpec` with `BinaryName`, `BinaryPath`, and command name.

Resolving and spawning Filebeat:

- `pkg/component/runtime/manager.go`
  - receives the component model and owns process runtime instances.
- `pkg/component/runtime/command.go`
  - `commandRuntime.start()` builds child env, args, workdir, and calls `process.Start(path, ...)`.
- `pkg/core/process/process.go`
  - starts the child process through `exec.Cmd`.
- `pkg/core/process/cmd.go`
  - appends `os.Environ()` and runtime-provided env to the child process.

## PQC_FILEBEAT_BIN Override

The Phase 1C override remains in `pkg/component/runtime`, immediately before `process.Start`.

When the component command name is `filebeat` and `PQC_FILEBEAT_BIN` points to a real file:

- Agent uses that file as the process binary.
- Agent keeps Fleet-generated args and config.
- Agent keeps stdout/stderr handling.
- Agent keeps workdir, monitoring, check-in, restart, stop, and teardown behavior.
- Metricbeat, Endpoint, Fleet Server, and other components are not affected.

If `PQC_FILEBEAT_BIN` is unset, behavior is unchanged.

If `PQC_FILEBEAT_BIN` is set but invalid, Agent logs a warning and falls back to the default Filebeat binary so Fleet-managed lifecycle is not broken.

## Phase 1C Test Package Layout

`elastic-agent install` is not a single-file install path. The installer discovers the directory containing `elastic-agent.exe`, verifies a package manifest, copies files into `C:\Program Files\Elastic\Agent`, then starts the service and enrolls.

For the PoC artifact, `tools/pqc-test/install-agent-fleet-pqc-windows.ps1` prepares the minimum layout before calling install:

```text
elastic-agent.exe
elastic-agent.yml
manifest.yaml
package.version
data\elastic-agent-<version>-<commit>\elastic-agent.exe
data\elastic-agent-<version>-<commit>\manifest.yaml
data\elastic-agent-<version>-<commit>\components\testbeat.exe
data\elastic-agent-<version>-<commit>\components\testbeat.spec.yml
```

The `testbeat.exe` file only satisfies Elastic Agent's component binary check. The actual Filebeat process path is still replaced at spawn time by `PQC_FILEBEAT_BIN`.

## PQC Env Forwarding

Agent forwards these parent env vars into the child component env list when present:

```text
LOGSTASH_TLS_CURVE_TYPES
LOGSTASH_TLS_MIN_VERSION
LOGSTASH_TLS_STRICT_PQC
```

The Windows install script sets these as Machine-level environment variables before installing the Agent service:

```powershell
[Environment]::SetEnvironmentVariable("PQC_FILEBEAT_BIN", "<path>", "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_CURVE_TYPES", "X25519MLKEM768", "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_MIN_VERSION", "1.3", "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_STRICT_PQC", "true", "Machine")
```

The same values are also set in the current PowerShell process so `install/enroll` can see them immediately.

## Expected Agent Log

When custom Filebeat is used:

```text
Using custom Filebeat binary from PQC_FILEBEAT_BIN
fleet_managed=true
component=filebeat
using_custom_filebeat=true
custom_filebeat_path=...
original_filebeat_path=...
child_env_pqc_enabled=true
logstash_tls_curve_types_present=true
logstash_tls_min_version_present=true
logstash_tls_strict_pqc_present=true
pqc_env_forwarded=true
policy_output=logstash
logstash_hosts=[192.168.22.171:5443]
```

`fleet_managed` is inferred from the installed Agent marker. It should be true for the Windows service install/enroll path.

## Fleet Policy Requirements

Use a Fleet policy with at least one Filebeat-backed input. For Phase 1C, use Custom logs first:

```text
C:\pqc-test\fleet-pqc-test.log
```

Set the policy output to Logstash:

```text
host: 192.168.22.171:5443
ssl: enabled
verification_mode: none for lab
```

If Fleet advanced YAML accepts the fields, use:

```yaml
ssl.enabled: true
ssl.verification_mode: none
ssl.curve_types: ["X25519MLKEM768"]
ssl.supported_protocols: ["TLSv1.3"]
ssl.strict_pqc: true
```

If Fleet rejects `ssl.curve_types` or `ssl.strict_pqc`, keep the basic Logstash TLS policy and rely on the env fallback. The custom Filebeat enforces PQC from env.

## Rollback

Uninstall Agent:

```powershell
elastic-agent uninstall --force
```

Remove Machine-level env:

```powershell
[Environment]::SetEnvironmentVariable("PQC_FILEBEAT_BIN", $null, "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_CURVE_TYPES", $null, "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_MIN_VERSION", $null, "Machine")
[Environment]::SetEnvironmentVariable("LOGSTASH_TLS_STRICT_PQC", $null, "Machine")
```

Clean test data if needed:

```powershell
Remove-Item C:\pqc-test -Recurse -Force
```

Use the official Elastic Agent installer to restore normal production behavior.

## Production Direction

`PQC_FILEBEAT_BIN` is a PoC bridge. Production packaging should replace this with one of:

- custom component artifact repository
- modified component manifest
- local artifact cache override
- official-compatible custom Filebeat artifact
- signed custom Elastic Agent package containing the PQC Filebeat component
