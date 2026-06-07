## test_phase

This repository contains SIEM PQC test artifacts.

Current useful folders:

- `siem-pqc-phase1`: Phase 1A Filebeat PQC test artifacts.
- `siem-pqc-phase1b`: Phase 1B standalone Elastic Agent PQC test artifacts.
- `siem-pqc-phase1c`: Phase 1C Fleet-managed Elastic Agent PQC test artifacts.
- `ncs-standalone-pqc`: no-Fleet standalone NCS Elastic Agent PQC installer, Sysmon/audit setup, and server receiver.

Windows quick test, chỉ tải một script:

```powershell
cd C:\Users\Administrator\Downloads

Invoke-WebRequest `
  -Uri "https://github.com/trithien2309/test_phase/raw/main/ncs-standalone-pqc/elastic-agent-ncs-standalone-install.ps1" `
  -OutFile ".\elastic-agent-ncs-standalone-install.ps1"

powershell -ExecutionPolicy Bypass -File .\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443
```

Windows quick test nếu đã clone/giải nén repo:

```powershell
cd .\ncs-standalone-pqc

powershell -ExecutionPolicy Bypass -File .\elastic-agent-ncs-standalone-install.ps1 `
  -GatewayHost "192.168.22.171" `
  -GatewayPort 5443
```

Legacy Linux AMD64 server binary:

- `spike1_server_linux_amd64`

After cloning on Linux, make it executable if needed:

```bash
chmod +x spike1_server_linux_amd64
```
