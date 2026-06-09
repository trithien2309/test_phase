# NCS Standalone PQC Elastic Agent

Folder này là đường test no-Fleet cho Windows client.

Flow:

```text
Windows client
  -> elastic-agent-ncs-standalone-install.ps1
  -> Elastic Agent standalone service
  -> filebeat-pqc-windows-amd64.exe
  -> TLS 1.3 + X25519MLKEM768
  -> PQC Gateway 192.168.22.171:5443
  -> raw Beats/Lumberjack
  -> Logstash :5044
  -> Elasticsearch / Kibana
```

Flow Linux v1:

```text
Linux client
  -> elastic-agent-ncs-linux-standalone-install.sh
  -> Elastic Agent standalone service
  -> filebeat-pqc-linux-amd64
  -> TLS 1.3 + X25519MLKEM768
  -> PQC Gateway 192.168.22.171:5443
  -> raw Beats/Lumberjack
  -> Logstash :5044
  -> Elasticsearch / Kibana
```

## Windows Quick Test - Chỉ Tải 1 Script

Mở PowerShell bằng quyền Administrator, tải một file script rồi chạy:

```powershell
cd C:\Users\Administrator\Downloads

Invoke-WebRequest `
  -Uri "https://github.com/trithien2309/test_phase/raw/main/ncs-standalone-pqc/elastic-agent-ncs-standalone-install.ps1" `
  -OutFile ".\elastic-agent-ncs-standalone-install.ps1"

powershell -ExecutionPolicy Bypass -File .\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443
```

Script sẽ tự tải implementation, Sysmon, GPO resources, Elastic Agent artifact và Filebeat PQC artifact từ GitHub.

## Linux Quick Test

Tải 1 file script rồi chạy:

```bash
curl -L \
  -o elastic-agent-ncs-linux-standalone-install.sh \
  https://github.com/trithien2309/test_phase/raw/main/ncs-standalone-pqc/elastic-agent-ncs-linux-standalone-install.sh

sudo bash ./elastic-agent-ncs-linux-standalone-install.sh \
  --gateway-host 192.168.22.171 \
  --gateway-port 5443
```

Luu y: ban Linux nay can them artifact `ncs-elastic-agent-pqc-linux-amd64.tar.gz` neu muon chay day du mot lenh. Script da support `--agent-package` va `--filebeat-pqc-package` de tro toi package local/da upload sau nay.

## Windows Quick Test - Clone/ZIP Cả Repo

Nếu đã clone hoặc giải nén cả repo, chạy tại folder này:

```powershell
cd C:\path\to\test_phase\ncs-standalone-pqc

powershell -ExecutionPolicy Bypass -File .\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443
```

Nếu Gateway chưa bật nhưng vẫn muốn cài trước:

```powershell
powershell -ExecutionPolicy Bypass -File .\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443 `
  -AllowGatewayOffline
```

Đường script cũ vẫn dùng được:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ncs\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443
```

## Script Sẽ Làm Gì

```text
[0/9] Preflight: Administrator, Windows x64, Gateway TCP
[1/9] Gỡ Elastic Agent cũ nếu có
[2/9] Download artifact từ GitHub hoặc dùng local zip
[3/9] Extract Elastic Agent PQC + Filebeat PQC
[4/9] Cài/cập nhật Sysmon64 và verify Sysmon channel
[5/9] Cấu hình Windows audit/PowerShell/event log policy
[6/9] Tạo Elastic Agent standalone config với 6 Windows channels
[7/9] Set machine-level PQC env cho Windows service
[8/9] Cài Elastic Agent standalone service
[9/9] Verify local: Agent, Sysmon, Filebeat PQC, 6 channels, PQC env, TLS/PQC marker nếu có
```

Artifact được tải mặc định từ:

```text
https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages
```

Script ưu tiên tên mới:

```text
ncs-elastic-agent-pqc-windows-amd64.zip
filebeat-pqc-windows-amd64.zip
```

Và tự fallback tên Agent artifact cũ đã test:

```text
elastic-agent-pqc-phase1c-windows-amd64-package.zip
```

## Windows Event Channels

Script cài/cập nhật Sysmon và cấu hình collect 6 channel:

```text
Microsoft-Windows-Sysmon/Operational
Security
System
Application
Windows PowerShell
Microsoft-Windows-PowerShell/Operational
```

## Expected Local Markers

Windows Agent/Filebeat logs:

```text
TLS handshake completed
tls_version="TLS 1.3"
configured_curve_preferences=["X25519MLKEM768"]
strict_pqc=true
```

Gateway logs:

```text
handshake ok tls_version=TLS 1.3
forwarding raw Beats/Lumberjack stream to 127.0.0.1:5044
client->logstash bytes=...
```
