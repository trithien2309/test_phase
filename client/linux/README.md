# NCS Elastic Agent PQC Linux Standalone

Linux v1 di theo cung mo hinh Windows standalone da test:

```text
Elastic Agent standalone
  -> spawn Filebeat PQC custom
  -> TLS 1.3 + X25519MLKEM768
  -> PQC Gateway :5443
  -> Logstash :5044
  -> Elasticsearch/Kibana
```

## Scope Linux v1

```text
Supported: Ubuntu 20.04, Ubuntu 22.04, Ubuntu 24.04
Test target: Ubuntu 24.04 x86_64
Unsupported in v1: Ubuntu 16/18, Debian, RHEL/CentOS/Rocky/Alma/Oracle, SUSE
```

## Package Naming And Sources

```text
Elastic Agent official:
  elastic-agent-9.4.2-linux-x86_64.tar.gz
  https://artifacts.elastic.co/downloads/beats/elastic-agent

NCS Filebeat PQC custom:
  filebeat-pqc-linux-amd64.zip
  https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1

Optional auditd bundle:
  ncs-linux-auditd-v3.7.8-minimal.tar.gz
```

Elastic Agent khong can custom Linux binary trong v1 vi Agent chi dong vai tro supervisor standalone. Phan bat buoc custom la Filebeat PQC, duoc Agent spawn thong qua `PQC_FILEBEAT_BIN`.

## Quick Run

```bash
sudo bash ./elastic-agent-ncs-linux-standalone-install.sh \
  --gateway-host 192.168.22.171 \
  --gateway-port 5443
```

Neu dung artifact local:

```bash
sudo bash ./elastic-agent-ncs-linux-standalone-install.sh \
  --gateway-host 192.168.22.171 \
  --gateway-port 5443 \
  --agent-package ./elastic-agent-9.4.2-linux-x86_64.tar.gz \
  --filebeat-pqc-package ./filebeat-pqc-linux-amd64.zip
```

## What The Installer Does

```text
[0/9] Preflight Ubuntu 20.04+ x86_64, systemd, gateway TCP
[1/9] Remove existing Elastic Agent service
[2/9] Resolve artifacts
      - Agent official from Elastic
      - Filebeat PQC custom from NCS artifact source
[3/9] Extract Agent/Filebeat/auditd resources
[4/9] Install or verify auditd
[5/9] Configure auditd policy
[6/9] Write Elastic Agent standalone config
[7/9] Write systemd PQC env
[8/9] Install Elastic Agent service
[9/9] Verify service, Filebeat PQC process, smoke log, PQC markers
```

## Log Sources

```text
/var/log/audit/audit.log
/var/log/auth.log
/var/log/syslog
/var/log/dpkg.log
/var/log/apt/history.log
/var/log/ncs-agent-smoke.log
```

Flow nay khong cau hinh rsyslog/syslog-ng forward UDP 514 de tranh bypass PQC Gateway.
