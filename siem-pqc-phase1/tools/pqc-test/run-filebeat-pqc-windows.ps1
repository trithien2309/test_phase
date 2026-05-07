$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$FilebeatBin = if ($env:FILEBEAT_BIN) { $env:FILEBEAT_BIN } else { Join-Path $RootDir "build\filebeat-pqc-windows-amd64.exe" }
$FilebeatConfig = if ($env:FILEBEAT_CONFIG) { $env:FILEBEAT_CONFIG } else { Join-Path $RootDir "tools\pqc-test\example-filebeat-pqc.yml" }

$env:LOGSTASH_TLS_CURVE_TYPES = if ($env:LOGSTASH_TLS_CURVE_TYPES) { $env:LOGSTASH_TLS_CURVE_TYPES } else { "X25519MLKEM768" }
$env:LOGSTASH_TLS_MIN_VERSION = if ($env:LOGSTASH_TLS_MIN_VERSION) { $env:LOGSTASH_TLS_MIN_VERSION } else { "1.3" }
$env:LOGSTASH_TLS_STRICT_PQC = if ($env:LOGSTASH_TLS_STRICT_PQC) { $env:LOGSTASH_TLS_STRICT_PQC } else { "true" }

Write-Host "Using filebeat binary: $FilebeatBin"
Write-Host "Using config: $FilebeatConfig"
Write-Host "LOGSTASH_TLS_CURVE_TYPES=$($env:LOGSTASH_TLS_CURVE_TYPES)"
Write-Host "LOGSTASH_TLS_MIN_VERSION=$($env:LOGSTASH_TLS_MIN_VERSION)"
Write-Host "LOGSTASH_TLS_STRICT_PQC=$($env:LOGSTASH_TLS_STRICT_PQC)"

& $FilebeatBin -c $FilebeatConfig -e -d "logstash,tls,pqc"

