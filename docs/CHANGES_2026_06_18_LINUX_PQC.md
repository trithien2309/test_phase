# Changes 2026-06-18: Linux Standalone PQC Installer

## Summary

Hom nay tap trung sua va on dinh phase Linux standalone cho du an SIEM PQC:

```text
Elastic Agent standalone on Ubuntu
  -> spawn Filebeat PQC custom
  -> TLS 1.3 + X25519MLKEM768
  -> PQC Gateway :5443
  -> Logstash :5044
  -> Elasticsearch/Kibana
```

Scope da chot trong ngay:

```text
Linux v1 chi support Ubuntu 20.04, 22.04, 24.04.
Target test hien tai: Ubuntu 24.04 x86_64.
Khong lam Debian/RHEL/CentOS/SUSE trong phase nay.
Fleet chua dung trong Linux phase nay, dang chay standalone.
```

## Commits

```text
6fc67c9 Prepare Ubuntu Linux PQC standalone installer
5f4f714 Fix Linux SHA256 metadata parsing
b3855b0 Fix Linux Agent versioned home for PQC component
```

Tat ca da duoc push len GitHub repo `trithien2309/test_phase`, branch `demo`.

## Files Changed

```text
README.md
elastic-agent-ncs-linux-standalone-install.sh
client/linux/README.md
client/linux/elastic-agent-ncs-linux-standalone-install.sh
client/linux/packages/manifest.json
client/linux/packages/SHA256SUMS.txt
docs/LINUX_UBUNTU_STANDALONE_PQC.md
docs/CHANGES_2026_06_18_LINUX_PQC.md
```

## 1. Chot Linux Package Naming Va Artifact Sources

Da chot ten artifact va nguon tai:

```text
Elastic Agent custom PQC:
  ncs-elastic-agent-pqc-linux-amd64.tar.gz
  GitHub Release: linux-pqc-phase1-v1

Filebeat PQC custom:
  filebeat-pqc-linux-amd64.zip
  https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1

Optional auditd bundle:
  ncs-linux-auditd-v3.7.8-minimal.tar.gz
```

Ly do Elastic Agent Linux phai dung custom:

```text
Agent custom co runtime override PQC_FILEBEAT_BIN.
Package custom chua component testbeat va testbeat.spec.yml cho filestream.
Filebeat PQC custom ep TLS 1.3 + X25519MLKEM768 strict.
```

Artifact URL sau khi publish:

```text
https://github.com/trithien2309/test_phase/releases/download/linux-pqc-phase1-v1/ncs-elastic-agent-pqc-linux-amd64.tar.gz
https://github.com/trithien2309/test_phase/releases/download/linux-pqc-phase1-v1/filebeat-pqc-linux-amd64.zip
```

## 2. Toi Gian Bootstrap Cho Ubuntu 20+

File wrapper:

```text
elastic-agent-ncs-linux-standalone-install.sh
```

Da sua de bootstrap toi thieu:

```text
client/linux/elastic-agent-ncs-linux-standalone-install.sh
client/linux/packages/manifest.json
client/linux/packages/SHA256SUMS.txt
client/linux/resources/auditd/conf/ubuntu_audit.rules
client/linux/resources/auditd/setup/ubuntu20/*.deb
client/linux/resources/auditd/setup/ubuntu22/*.deb
client/linux/resources/auditd/setup/ubuntu2404/*.deb
```

Da bo khoi bootstrap:

```text
centos_audit.rules
centos6_audit.rules
rhel6_audit.rules
suse12_audit.rules
suse12_sp5_audit.rules
oracle_rhel_centos7/*.rpm
```

Muc tieu: may Ubuntu test khong con tai nham cac goi Oracle/RHEL/CentOS/SUSE.

## 3. Fix Loi SHA256 Metadata Parsing

Loi gap tren Ubuntu:

```text
[FAIL] SHA256 mismatch for elastic-agent-9.4.2-linux-x86_64.tar.gz. expected=# actual=<real_hash>
```

Nguyen nhan:

```text
SHA256SUMS.txt hien tai chi co comment.
Parser cu dung awk so sanh $2 voi filename.
Dong comment dang co filename o cot thu 2 nen bi hieu nham expected hash la "#".
```

Da sua:

```text
expected_sha_for() bo qua dong comment va dong trong.
Chi chap nhan hash dai 64 ky tu hex.
Ho tro filename co tien to "*" hoac path.
Neu khong co hash hop le thi skip verification va in warning.
```

Da sua them `client/linux/packages/SHA256SUMS.txt` de comment khong nam o format giong hash record.

## 4. Fix Loi Filebeat PQC Khong Spawn

Sau khi installer chay xong tren Ubuntu, ket qua ban dau:

```text
[OK] Elastic Agent service is running
[OK] auditd service is running
[WARN] Filebeat PQC process not found yet
```

Agent log co loi:

```text
input not supported - ensure you have installed the correct flavor
component.id: filestream-default
state: FAILED
```

Nguyen nhan xac dinh:

```text
Elastic Agent official package co versioned home that la:
  /opt/Elastic/Agent/data/elastic-agent-dd9ee6

Script cu co the tu tao versioned home sai, vi fallback commit la "unknown":
  data/elastic-agent-9.4.2-unknown

Khi install, component binary/spec testbeat khong duoc dat vao dung versioned home.
Agent service khong load duoc testbeat.spec.yml nen bao input filestream not supported.
```

Da sua:

```text
agent_build_info() uu tien doc thu muc co san trong AGENT_DIR/data/elastic-agent-*.
Khong tu suy doan versioned home neu official tarball da co san versioned home.
ensure_agent_package_layout() dat testbeat va testbeat.spec.yml vao dung:
  ${AGENT_DIR}/${versioned_home}/components
```

Da them log debug trong installer:

```text
[INFO] Versioned home: data/elastic-agent-dd9ee6
[INFO] Component spec: /opt/ncs-elastic-agent-standalone/agent/data/elastic-agent-dd9ee6/components/testbeat.spec.yml
```

Da them verify sau install:

```text
[OK] Installed testbeat component files found: /opt/Elastic/Agent/data/elastic-agent-dd9ee6/components
```

Neu van thieu file, script se canh bao ro:

```text
[WARN] Installed testbeat component files are missing under .../components
```

## 5. Current Linux Installer Flow

Lenh test:

```bash
git clone -b demo https://github.com/trithien2309/test_phase.git
cd test_phase

sudo bash ./elastic-agent-ncs-linux-standalone-install.sh \
  --gateway-host 192.168.22.171 \
  --gateway-port 5443
```

Flow script:

```text
[0/9] Preflight
  - require root
  - require Linux x86_64/amd64
  - require Ubuntu 20.04+
  - check systemd, curl, tar
  - check TCP toi PQC Gateway

[1/9] Remove existing Elastic Agent
  - stop elastic-agent
  - uninstall neu co binary cu
  - clean systemd drop-in

[2/9] Download or use local PQC artifacts
  - metadata tu client/linux/packages hoac bootstrap URL
  - Agent custom PQC tu GitHub Release
  - Filebeat PQC custom tu repo artifact

[3/9] Extract PQC and auditd artifacts
  - Agent vao /opt/ncs-elastic-agent-standalone/agent
  - Filebeat PQC vao /opt/ncs-elastic-agent-standalone/filebeat/filebeat-pqc-linux-amd64
  - auditd resources vao /opt/ncs-elastic-agent-standalone/auditd

[4/9] Install or verify auditd
  - dung offline Ubuntu deb neu co
  - fallback apt-get install auditd

[5/9] Configure Linux audit policy
  - copy ubuntu_audit.rules
  - set auditd.conf rotation
  - augenrules --load
  - enable/restart auditd

[6/9] Create Elastic Agent standalone config
  - tao package layout dung versioned home official
  - tao testbeat component bang Filebeat PQC
  - write elastic-agent.yml output.logstash ve Gateway

[7/9] Set systemd PQC environment
  - /etc/ncs-elastic-agent/pqc.env
  - /etc/systemd/system/elastic-agent.service.d/10-ncs-pqc.conf

[8/9] Install Elastic Agent service
  - elastic-agent install --force --non-interactive
  - restart service

[9/9] Verify local
  - elastic-agent active
  - auditd active
  - testbeat component files ton tai
  - filebeat/testbeat process
  - append smoke log
  - search PQC markers
```

## 6. Expected Checks After Rerun

Sau khi pull ban moi va chay lai installer, can thay:

```text
[INFO] Versioned home: data/elastic-agent-dd9ee6
[OK] Installed testbeat component files found: /opt/Elastic/Agent/data/elastic-agent-dd9ee6/components
```

Lenh check tren Linux client:

```bash
sudo pgrep -af "testbeat|filebeat"

sudo grep -RhiE \
  "input not supported|TLS handshake completed|pqc_mode|configured_curve_preferences" \
  /opt/Elastic/Agent/data/*/logs | tail -n 80
```

Lenh check tren server monitor:

```bash
tail -f /home/ncs/pqc-phase1/pqc-gateway.log
```

Expected gateway:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes > 0
```

## 7. Notes

```text
Windows phase truoc do da PASS.
Linux phase da cai duoc Elastic Agent service va auditd tren Ubuntu 24.04.
Loi con lai trong ngay la component Filebeat PQC chua spawn do sai versioned home.
Da push fix versioned home, can rerun tren Ubuntu de xac nhan het "input not supported".
```

Neu Linux sau ban fix co handshake TLS 1.3 va log vao Kibana thi Linux standalone PQC co the xem la PASS cho phase hien tai.
