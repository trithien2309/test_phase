# Phase 1 PQC Agent Build

## Requirements

- Go `1.25.9` in this repo
- Internet access for `go build` and `go test` if dependencies are not already cached
- Git submodule for Beats:

```powershell
git submodule update --init --depth 1 beats
```

## Repo layout used by this patch

- `elastic-agent/`
- `elastic-agent/beats/`
- `elastic-agent/elastic-agent-libs/`

`beats` is the real Logstash output implementation. `elastic-agent-libs` is copied local and replaced in `go.mod` so the PQC TLS changes build from workspace.

## Recommended verification tests

```powershell
cd C:\Users\trith\Desktop\SIEM\elastic-agent\elastic-agent-libs
go test ./transport/tlscommon

cd C:\Users\trith\Desktop\SIEM\elastic-agent\beats
go test ./libbeat/outputs/logstash

cd C:\Users\trith\Desktop\SIEM\elastic-agent
go test ./internal/pkg/otel/translate -run 'Test(GetOtelConfig|GetBeatsAuthExtensionConfig|LogStashToExporter)'
```

Note: on this Windows host, one later rerun of `go test ./libbeat/outputs/logstash` was blocked by local application control when the generated test executable was launched. The package had already passed earlier after the dependency compatibility fix.

## Build Elastic Agent for Windows

From `elastic-agent/`:

```powershell
go build -o build\elastic-agent-pqc-windows-amd64.exe .
```

Built artifact:

- `build/elastic-agent-pqc-windows-amd64.exe`

## Build Filebeat PoC for Windows

From `elastic-agent/beats/`:

```powershell
go build -o ..\build\filebeat-pqc-windows-amd64.exe ./x-pack/filebeat
```

Built artifact:

- `build/filebeat-pqc-windows-amd64.exe`

## Cross-compile Filebeat PoC for Linux

From `elastic-agent/beats/`:

```powershell
$env:GOOS='linux'
$env:GOARCH='amd64'
$env:CGO_ENABLED='0'
go build -o ..\build\filebeat-pqc-linux-amd64 ./x-pack/filebeat
```

Built artifact:

- `build/filebeat-pqc-linux-amd64`

## Suggested next build commands

If you want full packaging later, run the normal Elastic build pipeline from this patched tree so the packaged components inherit the same Beats and TLS changes.

Examples:

```powershell
cd C:\Users\trith\Desktop\SIEM\elastic-agent
go build -o build\elastic-agent-pqc-windows-amd64.exe .

cd C:\Users\trith\Desktop\SIEM\elastic-agent\beats
go build -o ..\build\filebeat-pqc-windows-amd64.exe ./x-pack/filebeat
go build -o ..\build\filebeat-pqc-linux-amd64 ./x-pack/filebeat
```

## Known limitations

- This phase does not package a full custom Elastic Agent installer bundle yet.
- The proof artifact for the actual Logstash output path is the custom Filebeat binary.
- The root `elastic-agent` binary was built successfully, but full Fleet package assembly is a separate packaging task.
- Gateway-side proof of selected PQC group is still required because Go does not expose the negotiated group in client `ConnectionState`.

