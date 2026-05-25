param(
    [Parameter(Mandatory = $true)]
    [string]$FleetUrl,

    [Parameter(Mandatory = $true)]
    [string]$EnrollmentToken,

    [string]$ArtifactBaseUrl = "https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages",

    [string]$AgentPackageZip = "",

    [string]$FilebeatPqcZip = "",

    [string]$InstallRoot = "C:\ncs-elastic-agent",

    [string]$GpoCheckScript = "",

    [string]$GatewayHost = "192.168.22.171",

    [int]$GatewayPort = 5443,

    [switch]$Insecure
)

$ErrorActionPreference = "Stop"

$AgentZipName = "elastic-agent-pqc-phase1c-windows-amd64-package.zip"
$FilebeatZipName = "filebeat-pqc-windows-amd64.zip"

function Write-Phase {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated Administrator PowerShell."
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [switch]$Required
    )

    try {
        $result = Test-NetConnection -ComputerName $HostName -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($result) {
            Write-OK "TCP reachable: ${HostName}:${Port}"
            return
        }
    } catch {
        Write-Warn "Test-NetConnection failed for ${HostName}:${Port}: $($_.Exception.Message)"
    }

    if ($Required) {
        throw "Required TCP endpoint is not reachable: ${HostName}:${Port}"
    }
    Write-Warn "TCP endpoint is not reachable now: ${HostName}:${Port}. Continuing so Agent can still enroll/retry later."
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Write-Info "Downloading $Uri"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
    Write-OK "Downloaded: $Destination"
}

function Uninstall-ExistingElasticAgent {
    $svc = Get-Service elastic-agent -ErrorAction SilentlyContinue
    $candidatePaths = @(
        (Join-Path $env:ProgramFiles "Elastic\Agent\elastic-agent.exe")
    )
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    if ($programFilesX86) {
        $candidatePaths += (Join-Path $programFilesX86 "Elastic\Agent\elastic-agent.exe")
    }

    $installedAgent = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($installedAgent) {
        Write-Info "Uninstalling existing Elastic Agent using $installedAgent"
        try {
            & $installedAgent uninstall --force
            Write-OK "Existing Elastic Agent uninstall command completed"
        } catch {
            Write-Warn "Elastic Agent uninstall command failed: $($_.Exception.Message)"
        }
    } elseif ($svc) {
        Write-Warn "Elastic Agent service exists but installed binary was not found. Falling back to service cleanup."
    } else {
        Write-OK "No existing Elastic Agent service found"
        return
    }

    Start-Sleep -Seconds 3
    $svc = Get-Service elastic-agent -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Warn "Elastic Agent service still exists. Stopping and deleting service registration."
        Stop-Service elastic-agent -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        & sc.exe delete elastic-agent | Out-Null
        Start-Sleep -Seconds 2
    }
}

function Get-AgentBuildInfo {
    param([Parameter(Mandatory = $true)][string]$AgentExe)

    $version = "9.5.0"
    $commit = "unknown"

    try {
        $versionOutput = (& $AgentExe version --binary-only 2>&1 | Out-String)
        if ($versionOutput -match "Binary:\s+([0-9]+\.[0-9]+\.[0-9]+(?:-SNAPSHOT)?)") {
            $version = $Matches[1]
        }
        if ($versionOutput -match "commit\s+([A-Za-z0-9]+)") {
            $commit = $Matches[1]
        }
    } catch {
        Write-Warn "Could not read Elastic Agent binary version. Falling back to $version/$commit."
    }

    $shortCommit = $commit
    if ($shortCommit.Length -gt 6) {
        $shortCommit = $shortCommit.Substring(0, 6)
    }

    [PSCustomObject]@{
        Version = $version
        Commit = $commit
        ShortCommit = $shortCommit
        VersionedHome = "data\elastic-agent-$version-$shortCommit"
        VersionedHomeUnix = "data/elastic-agent-$version-$shortCommit"
    }
}

function Write-TestbeatSpec {
    param([Parameter(Mandatory = $true)][string]$Path)

    @'
version: 2
inputs:
  - name: log
    aliases:
      - logfile
      - event/file
    description: "Logfile"
    platforms: &platforms
      - linux/amd64
      - linux/arm64
      - darwin/amd64
      - darwin/arm64
      - windows/amd64
      - windows/arm64
      - container/amd64
      - container/arm64
    outputs: &outputs
      - elasticsearch
      - kafka
      - logstash
      - redis
    command: &command
      name: "filebeat"
      restart_monitoring_period: 5s
      maximum_restarts_per_period: 1
      timeouts:
        restart: 1s
      args:
        - "-E"
        - "setup.ilm.enabled=false"
        - "-E"
        - "setup.template.enabled=false"
        - "-E"
        - "management.enabled=true"
        - "-E"
        - "management.restart_on_output_change=true"
        - "-E"
        - "logging.level=info"
        - "-E"
        - "logging.to_stderr=true"
        - "-E"
        - "filebeat.config.modules.enabled=false"
        - "-E"
        - "logging.event_data.to_stderr=true"
        - "-E"
        - "logging.event_data.to_files=false"
  - name: filestream
    description: "Filestream"
    platforms: *platforms
    outputs: *outputs
    command: *command
  - name: winlog
    description: "Winlog"
    platforms: *platforms
    outputs: *outputs
    command: *command
'@ | Set-Content -Path $Path -Encoding UTF8
}

function Ensure-AgentPackageLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentExe,

        [Parameter(Mandatory = $true)]
        [string]$FilebeatPqcExe
    )

    $agentDir = Split-Path -Parent $AgentExe
    $agentFile = Split-Path -Leaf $AgentExe
    $canonicalAgentExe = Join-Path $agentDir "elastic-agent.exe"

    if ($agentFile -ne "elastic-agent.exe") {
        Write-Info "Creating canonical package binary: $canonicalAgentExe"
        Copy-Item -LiteralPath $AgentExe -Destination $canonicalAgentExe -Force
        $AgentExe = $canonicalAgentExe
    }

    $buildInfo = Get-AgentBuildInfo -AgentExe $AgentExe
    $versionedHome = Join-Path $agentDir $buildInfo.VersionedHome
    $componentsDir = Join-Path $versionedHome "components"

    New-Item -ItemType Directory -Force $versionedHome | Out-Null
    New-Item -ItemType Directory -Force $componentsDir | Out-Null

    Copy-Item -LiteralPath $AgentExe -Destination (Join-Path $versionedHome "elastic-agent.exe") -Force
    Copy-Item -LiteralPath $FilebeatPqcExe -Destination (Join-Path $componentsDir "testbeat.exe") -Force

    $specDestination = Join-Path $componentsDir "testbeat.spec.yml"
    $specCandidates = @(
        (Join-Path $agentDir "components\testbeat.spec.yml"),
        (Join-Path (Split-Path -Parent $PSCommandPath) "testbeat.spec.yml")
    )
    $specSource = $specCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($specSource) {
        Copy-Item -LiteralPath $specSource -Destination $specDestination -Force
    } else {
        Write-Warn "testbeat.spec.yml was not found near package. Writing a minimal NCS spec for log/filestream/winlog."
        Write-TestbeatSpec -Path $specDestination
    }

    Set-Content -Path (Join-Path $agentDir "package.version") -Value $buildInfo.Version -Encoding ASCII

    $configPath = Join-Path $agentDir "elastic-agent.yml"
    if (-not (Test-Path -LiteralPath $configPath)) {
        @'
outputs:
  default:
    type: elasticsearch
    hosts: ["http://127.0.0.1:9200"]
inputs: []
'@ | Set-Content -Path $configPath -Encoding UTF8
    }

    $manifestPath = Join-Path $agentDir "manifest.yaml"
    $manifest = @"
apiVersion: v1
kind: PackageManifest
package:
  version: $($buildInfo.Version)
  snapshot: false
  hash: $($buildInfo.Commit)
  versioned-home: $($buildInfo.VersionedHomeUnix)
  path-mappings:
    - $($buildInfo.VersionedHomeUnix): $($buildInfo.VersionedHomeUnix)
      manifest.yaml: $($buildInfo.VersionedHomeUnix)/manifest.yaml
"@
    Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $versionedHome "manifest.yaml") -Force

    Write-OK "Elastic Agent package layout is ready"
    Write-Info "Agent package dir: $agentDir"
    Write-Info "Versioned home: $versionedHome"
    Write-Info "Component placeholder: $(Join-Path $componentsDir 'testbeat.exe')"

    return $AgentExe
}

function Add-ReportLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    Add-Content -Path $Path -Value $Line -Encoding UTF8
    Write-Host "  $Line"
}

function Test-AuditSetting {
    param(
        [string]$Actual,
        [string]$Expected
    )

    if ($Expected -eq "Success and Failure") {
        return ($Actual -match "Success" -and $Actual -match "Failure")
    }
    return ($Actual -match [regex]::Escape($Expected))
}

function Invoke-NCSGpoAuditCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDir,

        [string]$ExternalScript = ""
    )

    $reportPath = Join-Path $LogDir "gpo-check.log"
    $auditCsvPath = Join-Path $LogDir "auditpol.csv"
    Set-Content -Path $reportPath -Value "NCS Windows audit/GPO verification - $(Get-Date -Format o)" -Encoding UTF8

    if ($ExternalScript -and (Test-Path -LiteralPath $ExternalScript)) {
        Add-ReportLine -Path $reportPath -Line "[INFO] External GPO script reference: $ExternalScript"
    } elseif ($ExternalScript) {
        Add-ReportLine -Path $reportPath -Line "[WARN] External GPO script not found: $ExternalScript"
    }

    $audits = @(
        @{ Name = "Directory Service Changes"; Value = "Success" },
        @{ Name = "Security Group Management"; Value = "Success" },
        @{ Name = "Special Logon"; Value = "Success" },
        @{ Name = "Logon"; Value = "Success and Failure" },
        @{ Name = "Account Lockout"; Value = "Failure" },
        @{ Name = "Other Account Management Events"; Value = "Success" },
        @{ Name = "Sensitive Privilege Use"; Value = "Success" },
        @{ Name = "Audit Policy Change"; Value = "Success" },
        @{ Name = "User Account Management"; Value = "Success" },
        @{ Name = "Process Creation"; Value = "Success" }
    )

    try {
        & auditpol.exe /get /category:* /r | Set-Content -Path $auditCsvPath -Encoding UTF8
        $csv = Import-Csv $auditCsvPath
        foreach ($audit in $audits) {
            $row = $csv | Where-Object { $_.Subcategory -eq $audit.Name } | Select-Object -First 1
            if (-not $row) {
                Add-ReportLine -Path $reportPath -Line "[WARN] Audit subcategory missing: $($audit.Name)"
                continue
            }

            $actual = $row.'Inclusion Setting'
            if (Test-AuditSetting -Actual $actual -Expected $audit.Value) {
                Add-ReportLine -Path $reportPath -Line "[OK] $($audit.Name) = $actual"
            } else {
                Add-ReportLine -Path $reportPath -Line "[WARN] $($audit.Name) = $actual, expected $($audit.Value)"
            }
        }
    } catch {
        Add-ReportLine -Path $reportPath -Line "[WARN] auditpol check failed: $($_.Exception.Message)"
    }

    $policyChecks = @(
        @{
            Name = "Include command line in process creation events"
            Path = "HKLM:\software\microsoft\windows\currentversion\policies\system\audit"
            Property = "ProcessCreationIncludeCmdLine_Enabled"
            Expected = 1
        },
        @{
            Name = "Turn on Module Logging"
            Path = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
            Property = "EnableModuleLogging"
            Expected = 1
        },
        @{
            Name = "Turn on PowerShell Script Block Logging"
            Path = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
            Property = "EnableScriptBlockLogging"
            Expected = 1
        }
    )

    foreach ($check in $policyChecks) {
        if (-not (Test-Path -Path $check.Path)) {
            Add-ReportLine -Path $reportPath -Line "[WARN] $($check.Name) registry path missing: $($check.Path)"
            continue
        }

        $value = (Get-ItemProperty -Path $check.Path -ErrorAction SilentlyContinue).$($check.Property)
        if ($value -eq $check.Expected) {
            Add-ReportLine -Path $reportPath -Line "[OK] $($check.Name) = enabled"
        } else {
            Add-ReportLine -Path $reportPath -Line "[WARN] $($check.Name) = $value, expected $($check.Expected)"
        }
    }

    Write-OK "GPO/audit verification report: $reportPath"
}

Assert-Administrator

$installRootFull = [System.IO.Path]::GetFullPath($InstallRoot)
$packagesDir = Join-Path $installRootFull "packages"
$agentDir = Join-Path $installRootFull "agent"
$filebeatDir = Join-Path $installRootFull "filebeat"
$logsDir = Join-Path $installRootFull "logs"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  NCS Elastic Agent PQC Installer (Windows)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

Write-Phase "[0/8] Preflight checks"
New-Item -ItemType Directory -Force -Path @($packagesDir, $agentDir, $filebeatDir, $logsDir) | Out-Null
$fleetUri = [Uri]$FleetUrl
$fleetPort = if ($fleetUri.Port -gt 0) { $fleetUri.Port } elseif ($fleetUri.Scheme -eq "https") { 443 } else { 80 }
Write-Info "Fleet URL: $FleetUrl"
Write-Info "Install root: $installRootFull"
Test-TcpPort -HostName $fleetUri.Host -Port $fleetPort -Required
Test-TcpPort -HostName $GatewayHost -Port $GatewayPort

Write-Phase "[1/8] Remove existing Elastic Agent"
Uninstall-ExistingElasticAgent

Write-Phase "[2/8] Download or use local PQC artifacts"
$agentZipPath = Join-Path $packagesDir $AgentZipName
$filebeatZipPath = Join-Path $packagesDir $FilebeatZipName
if ($AgentPackageZip) {
    Copy-Item -LiteralPath (Resolve-Path $AgentPackageZip).Path -Destination $agentZipPath -Force
    Write-OK "Using local Agent package: $AgentPackageZip"
} else {
    Invoke-Download -Uri "$($ArtifactBaseUrl.TrimEnd('/'))/$AgentZipName" -Destination $agentZipPath
}
if ($FilebeatPqcZip) {
    Copy-Item -LiteralPath (Resolve-Path $FilebeatPqcZip).Path -Destination $filebeatZipPath -Force
    Write-OK "Using local Filebeat PQC package: $FilebeatPqcZip"
} else {
    Invoke-Download -Uri "$($ArtifactBaseUrl.TrimEnd('/'))/$FilebeatZipName" -Destination $filebeatZipPath
}

Write-Phase "[3/8] Extract PQC artifacts"
if (Test-Path -LiteralPath $agentDir) { Remove-Item -LiteralPath $agentDir -Recurse -Force }
if (Test-Path -LiteralPath $filebeatDir) { Remove-Item -LiteralPath $filebeatDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path @($agentDir, $filebeatDir) | Out-Null
Expand-Archive -LiteralPath $agentZipPath -DestinationPath $agentDir -Force
Expand-Archive -LiteralPath $filebeatZipPath -DestinationPath $filebeatDir -Force
$elasticAgentExe = Join-Path $agentDir "elastic-agent.exe"
$filebeatPqcExe = Join-Path $filebeatDir "filebeat-pqc-windows-amd64.exe"
if (-not (Test-Path -LiteralPath $elasticAgentExe)) { throw "Elastic Agent binary not found after extraction: $elasticAgentExe" }
if (-not (Test-Path -LiteralPath $filebeatPqcExe)) { throw "Filebeat PQC binary not found after extraction: $filebeatPqcExe" }
Write-OK "Elastic Agent binary: $elasticAgentExe"
Write-OK "Filebeat PQC binary: $filebeatPqcExe"

Write-Phase "[4/8] Prepare Elastic Agent package layout"
$elasticAgentExe = Ensure-AgentPackageLayout -AgentExe $elasticAgentExe -FilebeatPqcExe $filebeatPqcExe

Write-Phase "[5/8] Set Machine-level PQC environment"
$machineEnv = @{
    "PQC_FILEBEAT_BIN" = $filebeatPqcExe
    "LOGSTASH_TLS_CURVE_TYPES" = "X25519MLKEM768"
    "LOGSTASH_TLS_MIN_VERSION" = "1.3"
    "LOGSTASH_TLS_STRICT_PQC" = "true"
}
foreach ($entry in $machineEnv.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Machine")
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    Write-OK "$($entry.Key) configured"
}

Write-Phase "[6/8] Verify Windows audit/GPO policy (read-only)"
Invoke-NCSGpoAuditCheck -LogDir $logsDir -ExternalScript $GpoCheckScript

Write-Phase "[7/8] Install and enroll Elastic Agent into Fleet"
$installArgs = @(
    "install",
    "--force",
    "--non-interactive",
    "--url=$FleetUrl",
    "--enrollment-token=$EnrollmentToken"
)
if ($Insecure) {
    $installArgs += "--insecure"
}
Write-Info "Running Elastic Agent install/enroll. Enrollment token is intentionally not printed."
& $elasticAgentExe @installArgs

Write-Phase "[8/8] Verify local install and print server checks"
Write-Host ""
Write-Host "Elastic Agent service:" -ForegroundColor Cyan
Get-Service elastic-agent | Format-Table -AutoSize

Write-Host ""
Write-Host "Filebeat child process check:" -ForegroundColor Cyan
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -like "*filebeat*" -or $_.CommandLine -like "*filebeat*" } |
    Select-Object ProcessId,Name,CommandLine |
    Format-List

Write-Host ""
Write-Host "Recent Agent/Filebeat PQC markers:" -ForegroundColor Cyan
$agentLogRoot = "C:\Program Files\Elastic\Agent\data"
if (Test-Path -LiteralPath $agentLogRoot) {
    Get-ChildItem "$agentLogRoot\elastic-agent-*\logs" -Filter "*.ndjson" -Recurse -ErrorAction SilentlyContinue |
        Select-String -Pattern "using_custom_filebeat|pqc_env_forwarded|Logstash PQC TLS mode configured|pqc_mode" -ErrorAction SilentlyContinue |
        Select-Object -Last 20 |
        ForEach-Object { $_.Line }
} else {
    Write-Warn "Agent log root not found yet: $agentLogRoot"
}

Write-Host ""
Write-Host "Server-side checks to run on Ubuntu monitor:" -ForegroundColor Cyan
Write-Host "  ss -lntp | grep -E ':5443|:5044'"
Write-Host "  journalctl -u siem-pqc-gateway -f"
Write-Host "  curl -k -u elastic:<PASSWORD> 'https://localhost:9200/_cat/indices/ncs-windows-pqc-*?v'"
Write-Host ""
Write-Host "Kibana Discover:"
Write-Host "  Data view: ncs-windows-pqc-*"
Write-Host "  Search: host.name : `"$env:COMPUTERNAME`""
Write-Host "  Search: event.code : `"4688`" or event.code : `"4104`""

Write-Host ""
Write-Host "NCS Elastic Agent PQC install flow completed." -ForegroundColor Green
