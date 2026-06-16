# Linux Ubuntu Standalone PQC Phase

## Current Scope

```text
Mode: Elastic Agent standalone
Supported OS: Ubuntu 20.04, 22.04, 24.04
Primary test target: Ubuntu 24.04 x86_64
Fleet: not used in this phase
Transport: Filebeat PQC -> PQC Gateway :5443 -> Logstash :5044
```

## Final Package Naming

```text
Elastic Agent official:
  elastic-agent-9.4.2-linux-x86_64.tar.gz

Filebeat PQC custom:
  filebeat-pqc-linux-amd64.zip

Optional auditd bundle:
  ncs-linux-auditd-v3.7.8-minimal.tar.gz
```

## Artifact Sources

```text
Elastic Agent:
  https://artifacts.elastic.co/downloads/beats/elastic-agent

Filebeat PQC custom:
  https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1

Bootstrap payload:
  https://raw.githubusercontent.com/trithien2309/test_phase/demo
```

Elastic Agent Linux is official in this phase because the PQC behavior lives in the custom Filebeat child process. The Agent only needs to run standalone and spawn Filebeat through `PQC_FILEBEAT_BIN`.

## Installer Command

```bash
sudo bash ./elastic-agent-ncs-linux-standalone-install.sh \
  --gateway-host 192.168.22.171 \
  --gateway-port 5443
```

With local artifacts:

```bash
sudo bash ./elastic-agent-ncs-linux-standalone-install.sh \
  --gateway-host 192.168.22.171 \
  --gateway-port 5443 \
  --agent-package ./elastic-agent-9.4.2-linux-x86_64.tar.gz \
  --filebeat-pqc-package ./filebeat-pqc-linux-amd64.zip
```

## Installer Flow

```text
[0/9] Preflight
  - require root
  - require Linux x86_64/amd64
  - require Ubuntu 20.04+
  - require systemd, curl, tar
  - check PQC Gateway TCP

[1/9] Remove existing Elastic Agent
  - stop elastic-agent
  - run existing elastic-agent uninstall if found
  - clean elastic-agent systemd drop-in
  - do not remove auditd logs

[2/9] Resolve artifacts
  - metadata from client/linux/packages or bootstrap URL
  - Agent from official Elastic source
  - Filebeat PQC from NCS custom source
  - auditd bundle optional

[3/9] Extract artifacts
  - Agent to /opt/ncs-elastic-agent-standalone/agent
  - Filebeat PQC to /opt/ncs-elastic-agent-standalone/filebeat/filebeat-pqc-linux-amd64
  - auditd resources to /opt/ncs-elastic-agent-standalone/auditd

[4/9] Install or verify auditd
  - Ubuntu 20/22/24 offline packages if available
  - fallback apt-get install auditd

[5/9] Configure auditd policy
  - write Ubuntu audit rules
  - set auditd.conf log rotation settings
  - load rules with augenrules
  - restart/enable auditd

[6/9] Create Elastic Agent standalone config
  - output.logstash to GatewayHost:GatewayPort
  - ssl TLS 1.3 + X25519MLKEM768 strict
  - filestream audit/auth/syslog/package/smoke logs

[7/9] Set systemd PQC env
  - /etc/ncs-elastic-agent/pqc.env
  - elastic-agent.service.d/10-ncs-pqc.conf

[8/9] Install Elastic Agent service
  - elastic-agent install --force --non-interactive
  - restart service

[9/9] Verify local
  - elastic-agent active
  - auditd active
  - filebeat-pqc-linux-amd64 process visible
  - smoke log appended
  - PQC markers searched in Agent logs
```

## Expected Proof

Client side:

```text
pqc_mode=enabled
tls_version=TLS 1.3
configured_curve_preferences=["X25519MLKEM768"]
strict_pqc=true
```

Gateway side:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes > 0
```

Kibana:

```text
data_stream.dataset : "ncs.linux.auditd"
data_stream.dataset : "ncs.linux.auth"
data_stream.dataset : "ncs.linux.syslog"
data_stream.dataset : "ncs.linux.package"
```

## Not In This Phase

```text
Fleet-managed Linux
Debian/RHEL/SUSE support
rsyslog/syslog-ng UDP forwarding
Suricata/Wazuh
Firewall/domain blocking
Production CA validation
```
