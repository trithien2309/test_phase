# Linux PQC Release And Ubuntu 24.04 Checklist

## Publish From Windows

Authenticate GitHub CLI once:

```powershell
gh auth login
```

Publish branch `demo` and all three Release assets:

```powershell
cd C:\Users\trith\Desktop\SIEM\elastic-agent\publish\test_phase_clone
powershell -ExecutionPolicy Bypass -File .\client\linux\publish-linux-pqc-release.ps1
```

The script verifies the local SHA256 values before pushing or uploading anything.

## Clean Ubuntu 24.04 Test

```bash
git clone -b demo https://github.com/trithien2309/test_phase.git
cd test_phase

sudo bash ./elastic-agent-ncs-linux-standalone-install.sh \
  --gateway-host 192.168.22.171 \
  --gateway-port 5443

sudo bash ./client/linux/check-linux-pqc-install.sh
```

The checker must exit with code `0`. Any `FAIL`, `input not supported`, or `unknown flavor` means the phase has not passed.

## Server Monitor

```bash
tail -f /home/ncs/pqc-phase1/pqc-gateway.log
```

Required evidence:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes > 0
```

The selected group must be proven by Gateway/OpenSSL output or packet capture. Go `ConnectionState` does not expose the negotiated group, so client logs only prove the configured preference.

## Kibana

Use one or more queries:

```text
data_stream.dataset : "ncs.linux.auditd"
data_stream.dataset : "ncs.linux.auth"
data_stream.dataset : "ncs.linux.syslog"
data_stream.dataset : "ncs.linux.package"
data_stream.dataset : "ncs.transport_smoke"
```

Linux standalone PQC passes only after the checker returns `0`, Gateway receives data, and Kibana shows an event from the Ubuntu host.

## Reproducibility Note

The Release artifacts are installable without the source tree. The current custom Agent, Beats, and `elastic-agent-libs` patches still live in the local Elastic source workspace. Before production, move those patches to dedicated forks or store a reviewed patch bundle so `source_commit` identifies the exact custom source rather than only the upstream base commit.
