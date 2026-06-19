# Changes 2026-06-19: Linux Custom Agent PQC Package

## Completed

- Replaced the Linux official Agent dependency with `ncs-elastic-agent-pqc-linux-amd64.tar.gz`.
- Added PowerShell and Bash package builders for Linux amd64.
- Packaged Filebeat PQC as the `testbeat` component with `filestream` and Logstash support.
- Changed package manifests to `version: co.elastic.agent/v1`.
- Removed fallback values such as `unknown` and `pqcdev` for package commit metadata.
- Added validation that rejects packages missing `testbeat`, `testbeat.spec.yml`, or the correct manifest version.
- Changed the default artifact source to GitHub Release `linux-pqc-phase1-v1`.
- Extended local verification to report `input not supported`, `unknown flavor`, PQC override, and TLS markers.

## Built Artifacts

```text
ncs-elastic-agent-pqc-linux-amd64.tar.gz
  size: 183545213 bytes
  sha256: DC79F7954B3D6E25302D89C7D4E313EE266D9CA8E9CD748341E1F3F4CCFF22F2

filebeat-pqc-linux-amd64.zip
  size: 94070565 bytes
  sha256: 70BE6E98BBD6524307A72983D24C05297DD10D5950B5A231255EDB3D3E5A22B7
```

Both binaries have Linux ELF headers. The Filebeat binary contains `X25519MLKEM768` and `pqc_mode`; the Agent binary contains `using_custom_filebeat`.

## Package Layout Verified

```text
ncs-elastic-agent-pqc-linux-amd64/
  elastic-agent
  manifest.yaml
  package.version
  data/elastic-agent-9.5.0-aa7920a1e9e9/
    elastic-agent
    manifest.yaml
    package.version
    components/
      testbeat
      testbeat.spec.yml
```

## Test Status

- `go test ./libbeat/outputs/logstash`: PASS.
- `go test ./transport/tlscommon`: PASS.
- Agent runtime test could not start because the Windows sandbox denied executable path resolution.
- Full `transport` test was blocked because the sandbox could not download missing Go modules.
- Ubuntu 24.04 installation and end-to-end Gateway/Kibana verification remain required after publishing the Release assets.
