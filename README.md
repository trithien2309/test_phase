# SIEM PQC Demo

Nhánh demo chỉ giữ các phần có thể chạy hoặc tiếp tục phát triển:

- Bộ cài Agent cho Windows
- PQC Gateway phía server
- Bộ cài Linux standalone tối thiểu cho Ubuntu 20.04+

## Cách cài đặt

### Cách 1: Cài tự động

1. Clone repo và chuyển sang nhánh demo.
2. Mở PowerShell bằng quyền Administrator.
3. Chạy lệnh:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\elastic-agent-ncs-standalone-install.ps1 -GatewayHost "192.168.22.171" -GatewayPort 5443
~~~

### Cách 2: Cài từ file local

Dùng cách này khi bạn đã tải sẵn 2 file zip:

- elastic-agent-pqc-phase1c-windows-amd64-package.zip
- filebeat-pqc-windows-amd64.zip

Chạy:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\elastic-agent-ncs-standalone-install.ps1 -GatewayHost "192.168.22.171" -GatewayPort 5443 -AgentPackageZip "C:\path\elastic-agent-pqc-phase1c-windows-amd64-package.zip" -FilebeatPqcZip "C:\path\filebeat-pqc-windows-amd64.zip"
~~~

## Linux

Linux v1 hiện chốt scope Ubuntu 20.04/22.04/24.04 x86_64, test chính trên Ubuntu 24.04:

~~~bash
sudo bash ./elastic-agent-ncs-linux-standalone-install.sh --gateway-host 192.168.22.171 --gateway-port 5443
~~~

Artifact Linux đã chốt:

- Elastic Agent official: `elastic-agent-9.4.2-linux-x86_64.tar.gz`
- Filebeat PQC custom: `filebeat-pqc-linux-amd64.zip`
- Bootstrap chỉ kéo Ubuntu auditd resources, không kéo CentOS/RHEL/SUSE trong phase này.

Chi tiết nằm trong `client/linux/README.md`.

## Server

PQC Gateway và pipeline Logstash nằm trong:

- server/pqc-gateway/
- server/logstash/pipeline/phase1-pqc-filebeat.conf
