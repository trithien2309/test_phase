$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$ConfigPath = if ($env:AGENT_STANDALONE_CONFIG) {
    $env:AGENT_STANDALONE_CONFIG
} else {
    Join-Path $RootDir "tools\pqc-test\elastic-agent-standalone-pqc.yml"
}

$AgentBin = if ($env:AGENT_BIN) {
    $env:AGENT_BIN
} elseif (Test-Path (Join-Path $RootDir "build\elastic-agent-pqc-windows-amd64.exe")) {
    Join-Path $RootDir "build\elastic-agent-pqc-windows-amd64.exe"
} else {
    Join-Path $RootDir "elastic-agent-pqc-windows-amd64.exe"
}

$FilebeatBin = if ($env:PQC_FILEBEAT_BIN) {
    $env:PQC_FILEBEAT_BIN
} elseif (Test-Path (Join-Path $RootDir "build\filebeat-pqc-windows-amd64.exe")) {
    Join-Path $RootDir "build\filebeat-pqc-windows-amd64.exe"
} else {
    Join-Path $RootDir "filebeat-pqc-windows-amd64.exe"
}

if (-not (Test-Path $AgentBin)) {
    throw "Elastic Agent binary not found: $AgentBin. Set AGENT_BIN to elastic-agent-pqc.exe."
}
if (-not (Test-Path $FilebeatBin)) {
    throw "Custom Filebeat binary not found: $FilebeatBin. Set PQC_FILEBEAT_BIN to filebeat-pqc-windows-amd64.exe."
}
if (-not (Test-Path $ConfigPath)) {
    throw "Standalone config not found: $ConfigPath. Set AGENT_STANDALONE_CONFIG if needed."
}

$AgentBinPath = (Resolve-Path $AgentBin).Path
$AgentDir = Split-Path -Parent $AgentBinPath
$ComponentHome = Join-Path $AgentDir "data\elastic-agent-9.5.0-unknown"
$ComponentDir = Join-Path $ComponentHome "components"
$SpecSource = if (Test-Path (Join-Path $RootDir "specs\testbeat.spec.yml")) {
    Join-Path $RootDir "specs\testbeat.spec.yml"
} elseif (Test-Path (Join-Path $RootDir "components\testbeat.spec.yml")) {
    Join-Path $RootDir "components\testbeat.spec.yml"
} else {
    throw "Cannot find testbeat.spec.yml. Expected specs\testbeat.spec.yml or components\testbeat.spec.yml under $RootDir."
}

New-Item -ItemType Directory -Force $ComponentDir | Out-Null
Set-Content -Path (Join-Path $AgentDir "package.version") -Value "9.5.0"
Copy-Item -LiteralPath $SpecSource -Destination (Join-Path $ComponentDir "testbeat.spec.yml") -Force
Copy-Item -LiteralPath $FilebeatBin -Destination (Join-Path $ComponentDir "testbeat.exe") -Force

New-Item -ItemType Directory -Force C:\pqc-test | Out-Null
$TestLog = "C:\pqc-test\agent-standalone-phase1b.log"
$Padding = "A" * 1600
Set-Content -Path $TestLog -Value "phase1b-agent-standalone-bootstrap $(Get-Date -Format o) $Padding"
Add-Content -Path $TestLog -Value "phase1b-agent-standalone-event $(Get-Date -Format o) $Padding"

$env:PQC_FILEBEAT_BIN = (Resolve-Path $FilebeatBin).Path
$env:LOGSTASH_TLS_CURVE_TYPES = if ($env:LOGSTASH_TLS_CURVE_TYPES) { $env:LOGSTASH_TLS_CURVE_TYPES } else { "X25519MLKEM768" }
$env:LOGSTASH_TLS_MIN_VERSION = if ($env:LOGSTASH_TLS_MIN_VERSION) { $env:LOGSTASH_TLS_MIN_VERSION } else { "1.3" }
$env:LOGSTASH_TLS_STRICT_PQC = if ($env:LOGSTASH_TLS_STRICT_PQC) { $env:LOGSTASH_TLS_STRICT_PQC } else { "true" }

Write-Host "Using Elastic Agent binary: $AgentBin"
Write-Host "Using custom Filebeat binary: $($env:PQC_FILEBEAT_BIN)"
Write-Host "Using standalone config: $ConfigPath"
Write-Host "Prepared component directory: $ComponentDir"
Write-Host "Test log: $TestLog"
Write-Host "LOGSTASH_TLS_CURVE_TYPES=$($env:LOGSTASH_TLS_CURVE_TYPES)"
Write-Host "LOGSTASH_TLS_MIN_VERSION=$($env:LOGSTASH_TLS_MIN_VERSION)"
Write-Host "LOGSTASH_TLS_STRICT_PQC=$($env:LOGSTASH_TLS_STRICT_PQC)"
Write-Host ""
Write-Host "While Agent is running, verify the child process with:"
Write-Host 'Get-CimInstance Win32_Process | Where-Object {$_.Name -like "*filebeat*"} | Select ProcessId,CommandLine'
Write-Host ""

& $AgentBinPath run -c $ConfigPath -e
