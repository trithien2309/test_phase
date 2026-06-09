# NCS Elastic Agent PQC Linux Standalone

Installer Linux nay chay theo cung flow voi ban Windows standalone:

```text
Elastic Agent standalone
  -> custom Filebeat PQC
  -> TLS 1.3 + X25519MLKEM768
  -> PQC Gateway :5443
  -> Logstash :5044
  -> Elasticsearch/Kibana
```

## Artifacts

Can upload hoac dat local cac file sau:

```text
elastic-agent-9.4.0-linux-x86_64.tar.gz
filebeat-pqc-linux-amd64.zip
```

`ncs-elastic-agent-pqc-linux-amd64.tar.gz` va `filebeat-pqc-linux-amd64.tar.gz` van duoc support neu ban co package custom rieng.
`ncs-linux-auditd-v3.7.8-minimal.tar.gz` la optional vi repo da kem auditd resources toi thieu trong `client/linux/resources/auditd`.

## Run

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
  --agent-package ./elastic-agent-9.4.0-linux-x86_64.tar.gz \
  --filebeat-pqc-package ./filebeat-pqc-linux-amd64.zip
```

Khi chay bang mot file wrapper tu GitHub, bootstrap chi tai payload toi thieu theo distro hien tai. Vi du Ubuntu 24.04 chi tai `ubuntu_audit.rules`, khong tai cac package `ubuntu20`, `ubuntu22`, `oracle_rhel_centos7`.

## Supported Linux v1

```text
Ubuntu 20.04, 22.04, 24.04
Debian 10+
RHEL/CentOS/Rocky/Alma/Oracle 7+
x86_64/amd64 only
```

Ubuntu 16/18 bi loai khoi v1.

## Log Sources

```text
/var/log/audit/audit.log
/var/log/auth.log
/var/log/secure
/var/log/syslog
/var/log/messages
/var/log/dpkg.log
/var/log/apt/history.log
/var/log/yum.log
/var/log/dnf.log
/var/log/ncs-agent-smoke.log
```

Khong cau hinh rsyslog/syslog-ng forward UDP 514 trong flow nay.
