$ErrorActionPreference = "Continue"

Write-Host "Elastic Agent service"
Get-Service elastic-agent | Format-Table -AutoSize

Write-Host ""
Write-Host "Elastic Agent process"
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -like "elastic-agent*" } |
    Select-Object ProcessId,Name,CommandLine |
    Format-List

Write-Host ""
Write-Host "Filebeat child process"
$filebeatProcesses = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -like "*filebeat*" -or $_.CommandLine -like "*filebeat*" } |
    Select-Object ProcessId,Name,CommandLine
$filebeatProcesses | Format-List

$pqcFilebeat = [Environment]::GetEnvironmentVariable("PQC_FILEBEAT_BIN", "Machine")
if ($pqcFilebeat) {
    $customProc = $filebeatProcesses | Where-Object { $_.CommandLine -like "*$([System.IO.Path]::GetFileName($pqcFilebeat))*" -or $_.CommandLine -like "*$pqcFilebeat*" }
    Write-Host ""
    Write-Host "Custom Filebeat process match: $([bool]$customProc)"
}

Write-Host ""
Write-Host "Machine-level PQC environment"
$envNames = @(
    "PQC_FILEBEAT_BIN",
    "LOGSTASH_TLS_CURVE_TYPES",
    "LOGSTASH_TLS_MIN_VERSION",
    "LOGSTASH_TLS_STRICT_PQC"
)
foreach ($name in $envNames) {
    $value = [Environment]::GetEnvironmentVariable($name, "Machine")
    if ($name -eq "PQC_FILEBEAT_BIN") {
        Write-Host "$name=$value"
    } else {
        Write-Host "$name present=$([bool]$value)"
    }
}

Write-Host ""
Write-Host "Recent Agent logs containing custom Filebeat markers"
$agentRoots = @(
    "C:\Program Files\Elastic\Agent",
    "C:\Elastic\Agent"
) | Where-Object { Test-Path $_ }

$logFiles = foreach ($root in $agentRoots) {
    Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "elastic-agent*.ndjson" -or $_.Name -like "elastic-agent*.log" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10
}

if (-not $logFiles) {
    Write-Host "No Elastic Agent log files found under common install paths."
} else {
    $logFiles | Select-Object FullName,LastWriteTime | Format-Table -AutoSize
    foreach ($file in $logFiles) {
        Select-String -Path $file.FullName -Pattern "using_custom_filebeat|PQC_FILEBEAT_BIN|child_env_pqc_enabled|pqc_env_forwarded" -ErrorAction SilentlyContinue |
            Select-Object -Last 20 |
            ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line)" }
    }
}

Write-Host ""
Write-Host "Useful paths"
Write-Host "Agent logs: C:\Program Files\Elastic\Agent\data\elastic-agent-*\logs"
Write-Host "Filebeat test log: C:\pqc-test\fleet-pqc-test.log"

Write-Host ""
Write-Host "Append another test event with:"
Write-Host 'Add-Content C:\pqc-test\fleet-pqc-test.log "fleet-pqc-event $(Get-Date -Format o)"'
