$ErrorActionPreference = "Stop"

$AgentBin = if ($env:AGENT_BIN) { $env:AGENT_BIN } else { ".\build\elastic-agent-pqc-windows-amd64.exe" }
$FleetUrl = if ($env:FLEET_URL) { $env:FLEET_URL } else { "https://fleet.example.local:8220" }
$EnrollmentToken = if ($env:ENROLLMENT_TOKEN) { $env:ENROLLMENT_TOKEN } else { "REPLACE_ME" }

$env:LOGSTASH_TLS_CURVE_TYPES = if ($env:LOGSTASH_TLS_CURVE_TYPES) { $env:LOGSTASH_TLS_CURVE_TYPES } else { "X25519MLKEM768" }
$env:LOGSTASH_TLS_MIN_VERSION = if ($env:LOGSTASH_TLS_MIN_VERSION) { $env:LOGSTASH_TLS_MIN_VERSION } else { "1.3" }
$env:LOGSTASH_TLS_STRICT_PQC = if ($env:LOGSTASH_TLS_STRICT_PQC) { $env:LOGSTASH_TLS_STRICT_PQC } else { "true" }

Write-Host "LOGSTASH_TLS_CURVE_TYPES=$($env:LOGSTASH_TLS_CURVE_TYPES)"
Write-Host "LOGSTASH_TLS_MIN_VERSION=$($env:LOGSTASH_TLS_MIN_VERSION)"
Write-Host "LOGSTASH_TLS_STRICT_PQC=$($env:LOGSTASH_TLS_STRICT_PQC)"

& $AgentBin enroll `
  --url $FleetUrl `
  --enrollment-token $EnrollmentToken `
  --insecure

& $AgentBin run -e -d "logstash,tls,pqc"
