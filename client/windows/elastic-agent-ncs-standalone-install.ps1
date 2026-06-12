param(
    [string]$ArtifactBaseUrl = "https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages",

    [string]$ArtifactPrivateToken = "",

    [string]$AgentPackageZip = "",

    [string]$FilebeatPqcZip = "",

    [string]$InstallRoot = "C:\ncs-elastic-agent-standalone",

    [string]$GatewayHost = "192.168.22.171",

    [int]$GatewayPort = 5443,

    [string]$GpoCheckScript = "",

    [string]$SmokeLogPath = "C:\pqc-test\ncs-agent-smoke.log",

    [switch]$AllowGatewayOffline,

    [switch]$VerifyOnlyWindowsLogging
)

$ErrorActionPreference = "Stop"

$AgentZipNames = @(
    "ncs-elastic-agent-pqc-windows-amd64.zip",
    "elastic-agent-pqc-phase1c-windows-amd64-package.zip"
)
$FilebeatZipNames = @("filebeat-pqc-windows-amd64.zip")
$ManifestName = "manifest.json"
$Sha256Name = "SHA256SUMS.txt"

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

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Get-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $candidate = Resolve-Path (Join-Path $scriptDir "..\..") -ErrorAction SilentlyContinue
    if ($candidate) {
        return $candidate.Path
    }
    return (Get-Location).Path
}

function Get-ResourceRoot {
    return (Join-Path (Split-Path -Parent $PSCommandPath) "resources")
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated Administrator PowerShell."
    }
}

function Assert-WindowsX64 {
    if ($env:OS -ne "Windows_NT") {
        throw "This installer is Windows-only."
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "This installer requires Windows x64."
    }
    Write-OK "Windows x64 detected"
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [switch]$AllowOffline
    )

    try {
        $result = Test-NetConnection -ComputerName $HostName -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($result) {
            Write-OK "TCP reachable: ${HostName}:${Port}"
            return
        }

        if ($AllowOffline) {
            Write-Warn "TCP endpoint is not reachable now: ${HostName}:${Port}. Continuing because -AllowGatewayOffline is set."
            return
        }

        throw "PQC Gateway is not reachable: ${HostName}:${Port}. Start the gateway or rerun with -AllowGatewayOffline."
    } catch {
        if ($AllowOffline) {
            Write-Warn "Gateway preflight failed for ${HostName}:${Port}: $($_.Exception.Message)"
            return
        }
        throw
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$PrivateToken = ""
    )

    Write-Info "Downloading $Uri"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($PrivateToken) {
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -Headers @{ "PRIVATE-TOKEN" = $PrivateToken }
    } else {
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
    }
    Write-OK "Downloaded: $Destination"
}

function Get-ArtifactSearchDirs {
    $repoRoot = Get-RepoRoot
    $scriptDir = Split-Path -Parent $PSCommandPath
    return @(
        (Join-Path $repoRoot "packages"),
        (Join-Path (Get-Location).Path "packages"),
        (Join-Path $scriptDir "packages"),
        (Join-Path $scriptDir "..\..\packages")
    )
}

function Resolve-LocalArtifactByName {
    param([Parameter(Mandatory = $true)][string[]]$Names)

    foreach ($dir in Get-ArtifactSearchDirs) {
        foreach ($name in $Names) {
            $resolved = Resolve-Path (Join-Path $dir $name) -ErrorAction SilentlyContinue
            if ($resolved) {
                return $resolved.Path
            }
        }
    }

    return ""
}

function Copy-OrDownloadArtifact {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$ExplicitPath = ""
    )

    if ($ExplicitPath) {
        $resolved = Resolve-Path $ExplicitPath
        Copy-Item -LiteralPath $resolved.Path -Destination $Destination -Force
        Write-OK "Using explicit artifact: $($resolved.Path)"
        return
    }

    $localArtifact = Resolve-LocalArtifactByName -Names $Names
    if ($localArtifact) {
        Copy-Item -LiteralPath $localArtifact -Destination $Destination -Force
        Write-OK "Using bundled artifact: $localArtifact"
        return
    }

    if (-not $ArtifactBaseUrl) {
        throw "Artifact not found locally and -ArtifactBaseUrl is empty. Expected one of: $($Names -join ', ')"
    }

    $errors = @()
    foreach ($name in $Names) {
        $uri = "$($ArtifactBaseUrl.TrimEnd('/'))/$name"
        try {
            Invoke-Download -Uri $uri -Destination $Destination -PrivateToken $ArtifactPrivateToken
            return
        } catch {
            $errors += "$name => $($_.Exception.Message)"
            Write-Warn "Download failed for $name, trying next candidate if available."
        }
    }

    throw "Could not download artifact. Tried: $($Names -join ', '). Errors: $($errors -join ' | ')"
}

function Try-PrepareMetadataFile {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $local = Resolve-LocalArtifactByName -Names @($Name)
    if ($local) {
        Copy-Item -LiteralPath $local -Destination $Destination -Force
        Write-OK "Using metadata file: $local"
        return $true
    }

    if (-not $ArtifactBaseUrl) {
        Write-Warn "No metadata source for $Name"
        return $false
    }

    try {
        Invoke-Download -Uri "$($ArtifactBaseUrl.TrimEnd('/'))/$Name" -Destination $Destination -PrivateToken $ArtifactPrivateToken
        return $true
    } catch {
        Write-Warn "Could not download optional metadata ${Name}: $($_.Exception.Message)"
        return $false
    }
}

function Get-Sha256Map {
    param([Parameter(Mandatory = $true)][string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*([A-Fa-f0-9]{64})\s+\*?(.+?)\s*$") {
            $map[$Matches[2]] = $Matches[1].ToUpperInvariant()
        }
    }
    return $map
}

function Test-ArtifactHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$ShaMap,
        [Parameter(Mandatory = $true)][string[]]$CandidateNames
    )

    if ($ShaMap.Count -eq 0) {
        Write-Warn "SHA256SUMS.txt is not available; skipping hash verification for $(Split-Path -Leaf $Path)."
        return
    }

    $expected = ""
    foreach ($name in $CandidateNames) {
        if ($ShaMap.ContainsKey($name)) {
            $expected = $ShaMap[$name]
            break
        }
    }

    if (-not $expected) {
        Write-Warn "No checksum entry found for $(Split-Path -Leaf $Path)."
        return
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "SHA256 mismatch for $(Split-Path -Leaf $Path). expected=$expected actual=$actual"
    }
    Write-OK "SHA256 verified: $(Split-Path -Leaf $Path)"
}

function Show-ManifestInfo {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return
    }

    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        Write-Info "Manifest: $($manifest.name) $($manifest.version) / $($manifest.phase)"
    } catch {
        Write-Warn "Could not parse manifest.json: $($_.Exception.Message)"
    }
}

function Get-ElasticAgentService {
    $svc = Get-Service -Name "elastic-agent" -ErrorAction SilentlyContinue
    if (-not $svc) {
        $svc = Get-Service -Name "Elastic Agent" -ErrorAction SilentlyContinue
    }
    if (-not $svc) {
        $svc = Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq "Elastic Agent" -or $_.Name -like "*elastic*agent*" } |
            Select-Object -First 1
    }
    return $svc
}

function Uninstall-ExistingElasticAgent {
    $candidatePaths = @((Join-Path $env:ProgramFiles "Elastic\Agent\elastic-agent.exe"))
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    if ($programFilesX86) {
        $candidatePaths += (Join-Path $programFilesX86 "Elastic\Agent\elastic-agent.exe")
    }

    $installedAgent = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $svc = Get-ElasticAgentService

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
    $svc = Get-ElasticAgentService
    if ($svc) {
        Write-Warn "Elastic Agent service still exists as '$($svc.Name)'. Stopping and deleting service registration."
        Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        & sc.exe delete $svc.Name | Out-Null
        Start-Sleep -Seconds 2
    }
}

function Resolve-ExtractedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $direct = Join-Path $Root $name
        if (Test-Path -LiteralPath $direct) {
            return $direct
        }
    }

    foreach ($name in $Names) {
        $found = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    return ""
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
  - name: winlog
    description: "Winlog"
    platforms: &platforms
      - windows/amd64
      - windows/arm64
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
'@ | Set-Content -Path $Path -Encoding UTF8
}

function Ensure-AgentPackageLayout {
    param(
        [Parameter(Mandatory = $true)][string]$AgentExe,
        [Parameter(Mandatory = $true)][string]$FilebeatPqcExe
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
        Write-Warn "testbeat.spec.yml was not found near package. Writing a minimal NCS winlog spec."
        Write-TestbeatSpec -Path $specDestination
    }

    Set-Content -Path (Join-Path $agentDir "package.version") -Value $buildInfo.Version -Encoding ASCII

    $manifestPath = Join-Path $agentDir "manifest.yaml"
    $manifest = @"
apiVersion: v1
kind: PackageManifest
package:
  version: $($buildInfo.Version)
  snapshot: false
  hash: $($buildInfo.Commit)
  versioned-home: $($buildInfo.VersionedHomeUnix)
  flavors:
    basic:
      - testbeat
    servers:
      - testbeat
  path-mappings:
    - $($buildInfo.VersionedHomeUnix): $($buildInfo.VersionedHomeUnix)
      manifest.yaml: $($buildInfo.VersionedHomeUnix)/manifest.yaml
"@
    Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $versionedHome "manifest.yaml") -Force

    Write-OK "Elastic Agent package layout is ready"
    Write-Info "Agent package dir: $agentDir"
    Write-Info "Versioned home: $versionedHome"

    return $AgentExe
}

function Get-NCSWindowsEventChannels {
    return @(
        @{ Name = "Microsoft-Windows-Sysmon/Operational"; Dataset = "ncs.windows.sysmon" },
        @{ Name = "Security"; Dataset = "ncs.windows.security" },
        @{ Name = "System"; Dataset = "ncs.windows.system" },
        @{ Name = "Application"; Dataset = "ncs.windows.application" },
        @{ Name = "Windows PowerShell"; Dataset = "ncs.windows.powershell" },
        @{ Name = "Microsoft-Windows-PowerShell/Operational"; Dataset = "ncs.windows.powershell_operational" }
    )
}

function Write-StandaloneConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$LogstashHost
    )

    $lines = @(
        "agent:",
        "  logging:",
        "    level: debug",
        "    to_stderr: true",
        "    to_files: true",
        "  monitoring:",
        "    enabled: false",
        "  internal:",
        "    runtime:",
        "      output:",
        "        logstash: process",
        "",
        "outputs:",
        "  default:",
        "    type: logstash",
        "    hosts: [""$LogstashHost""]",
        "    ssl.enabled: true",
        "    ssl.verification_mode: none",
        "    ssl.curve_types: [""X25519MLKEM768""]",
        "    ssl.supported_protocols: [""TLSv1.3""]",
        "    ssl.strict_pqc: true",
        "",
        "inputs:",
        "  - id: ncs-windows-events",
        "    type: winlog",
        "    use_output: default",
        "    data_stream:",
        "      namespace: default",
        "    streams:"
    )

    foreach ($channel in Get-NCSWindowsEventChannels) {
        $id = ($channel.Dataset -replace "\.", "-")
        $lines += @(
            "      - id: $id",
            "        name: ""$($channel.Name)""",
            "        data_stream:",
            "          type: logs",
            "          dataset: $($channel.Dataset)",
            "        ignore_older: 72h"
        )
    }

    $config = ($lines -join "`r`n") + "`r`n"
    Set-Content -Path $ConfigPath -Value $config -Encoding UTF8
    Write-OK "Standalone Elastic Agent config written: $ConfigPath"
}

function Add-ReportLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Line
    )

    Add-Content -Path $Path -Value $Line -Encoding UTF8
    Write-Host "  $Line"
}

function Set-EventLogChannel {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int64]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [switch]$Enable
    )

    try {
        $args = @("sl", $Name, "/ms:$MaxBytes")
        if ($Enable) {
            $args += "/e:true"
        }
        & wevtutil.exe @args | Out-Null
        Add-ReportLine -Path $ReportPath -Line "[OK] event log configured: $Name max_bytes=$MaxBytes"
    } catch {
        Add-ReportLine -Path $ReportPath -Line "[WARN] failed to configure event log ${Name}: $($_.Exception.Message)"
    }
}

function Test-AuditSetting {
    param([string]$Actual, [string]$Expected)
    if ($Expected -eq "Success and Failure") {
        return ($Actual -match "Success" -and $Actual -match "Failure")
    }
    return ($Actual -match [regex]::Escape($Expected))
}

function Enable-NCSWindowsLoggingPolicy {
    param([Parameter(Mandatory = $true)][string]$ReportPath)

    Add-ReportLine -Path $ReportPath -Line "[INFO] Applying local Windows audit and PowerShell logging policy."

    Set-EventLogChannel -Name "Security" -MaxBytes 1048576000 -ReportPath $ReportPath
    Set-EventLogChannel -Name "System" -MaxBytes 262144000 -ReportPath $ReportPath
    Set-EventLogChannel -Name "Application" -MaxBytes 262144000 -ReportPath $ReportPath
    Set-EventLogChannel -Name "Windows PowerShell" -MaxBytes 262144000 -ReportPath $ReportPath
    Set-EventLogChannel -Name "Microsoft-Windows-PowerShell/Operational" -MaxBytes 524288000 -ReportPath $ReportPath -Enable
    Set-EventLogChannel -Name "Microsoft-Windows-Sysmon/Operational" -MaxBytes 524288000 -ReportPath $ReportPath -Enable

    $auditCommands = @(
        @{ Name = "Security Group Management"; Args = @("/set", "/subcategory:Security Group Management", "/success:enable") },
        @{ Name = "Other Account Management Events"; Args = @("/set", "/subcategory:Other Account Management Events", "/success:enable") },
        @{ Name = "User Account Management"; Args = @("/set", "/subcategory:User Account Management", "/success:enable") },
        @{ Name = "Process Creation"; Args = @("/set", "/subcategory:Process Creation", "/success:enable") },
        @{ Name = "Directory Service Changes"; Args = @("/set", "/subcategory:Directory Service Changes", "/success:enable") },
        @{ Name = "Directory Service Access"; Args = @("/set", "/subcategory:Directory Service Access", "/success:enable") },
        @{ Name = "Account Lockout"; Args = @("/set", "/subcategory:Account Lockout", "/failure:enable") },
        @{ Name = "Logon"; Args = @("/set", "/subcategory:Logon", "/success:enable", "/failure:enable") },
        @{ Name = "Special Logon"; Args = @("/set", "/subcategory:Special Logon", "/success:enable") },
        @{ Name = "File Share"; Args = @("/set", "/subcategory:File Share", "/success:enable") },
        @{ Name = "Other Object Access Events"; Args = @("/set", "/subcategory:Other Object Access Events", "/success:enable") },
        @{ Name = "Filtering Platform Packet Drop"; Args = @("/set", "/subcategory:Filtering Platform Packet Drop", "/success:disable", "/failure:disable") },
        @{ Name = "Filtering Platform Connection"; Args = @("/set", "/subcategory:Filtering Platform Connection", "/success:disable", "/failure:disable") },
        @{ Name = "Audit Policy Change"; Args = @("/set", "/subcategory:Audit Policy Change", "/success:enable") },
        @{ Name = "Authentication Policy Change"; Args = @("/set", "/subcategory:Authentication Policy Change", "/success:enable") },
        @{ Name = "Sensitive Privilege Use"; Args = @("/set", "/subcategory:Sensitive Privilege Use", "/success:enable") }
    )

    foreach ($cmd in $auditCommands) {
        try {
            & auditpol.exe @($cmd.Args) | Out-Null
            Add-ReportLine -Path $ReportPath -Line "[OK] audit policy applied: $($cmd.Name)"
        } catch {
            Add-ReportLine -Path $ReportPath -Line "[WARN] failed to apply audit policy $($cmd.Name): $($_.Exception.Message)"
        }
    }

    $registrySettings = @(
        @{
            Name = "Force Advanced Audit Policy"
            Path = "HKLM:\System\CurrentControlSet\Control\Lsa"
            Values = @{ "SCENoApplyLegacyAuditPolicy" = 1 }
        },
        @{
            Name = "Include command line in process creation events"
            Path = "HKLM:\software\microsoft\windows\currentversion\policies\system\audit"
            Values = @{ "ProcessCreationIncludeCmdLine_Enabled" = 1 }
        },
        @{
            Name = "Turn on Module Logging"
            Path = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
            Values = @{ "EnableModuleLogging" = 1 }
        },
        @{
            Name = "PowerShell ModuleLogging ModuleNames"
            Path = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames"
            Values = @{ "*" = "*" }
        },
        @{
            Name = "Turn on PowerShell Script Block Logging"
            Path = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
            Values = @{ "EnableScriptBlockLogging" = 1; "EnableScriptBlockInvocationLogging" = 1 }
        }
    )

    foreach ($setting in $registrySettings) {
        try {
            if (-not (Test-Path -Path $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
            }
            foreach ($value in $setting.Values.GetEnumerator()) {
                if ($value.Value -is [int]) {
                    New-ItemProperty -Path $setting.Path -Name $value.Key -Value $value.Value -PropertyType DWord -Force | Out-Null
                } else {
                    New-ItemProperty -Path $setting.Path -Name $value.Key -Value $value.Value -PropertyType String -Force | Out-Null
                }
            }
            Add-ReportLine -Path $ReportPath -Line "[OK] registry policy applied: $($setting.Name)"
        } catch {
            Add-ReportLine -Path $ReportPath -Line "[WARN] failed to apply registry policy $($setting.Name): $($_.Exception.Message)"
        }
    }
}

function Test-NCSWindowsLoggingPolicy {
    param([Parameter(Mandatory = $true)][string]$ReportPath)

    $auditCsvPath = Join-Path (Split-Path -Parent $ReportPath) "auditpol.csv"
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
                Add-ReportLine -Path $ReportPath -Line "[WARN] Audit subcategory missing: $($audit.Name)"
                continue
            }

            $actual = $row.'Inclusion Setting'
            if (Test-AuditSetting -Actual $actual -Expected $audit.Value) {
                Add-ReportLine -Path $ReportPath -Line "[OK] $($audit.Name) = $actual"
            } else {
                Add-ReportLine -Path $ReportPath -Line "[WARN] $($audit.Name) = $actual, expected $($audit.Value)"
            }
        }
    } catch {
        Add-ReportLine -Path $ReportPath -Line "[WARN] auditpol check failed: $($_.Exception.Message)"
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
            Add-ReportLine -Path $ReportPath -Line "[WARN] $($check.Name) registry path missing: $($check.Path)"
            continue
        }

        $value = (Get-ItemProperty -Path $check.Path -ErrorAction SilentlyContinue).$($check.Property)
        if ($value -eq $check.Expected) {
            Add-ReportLine -Path $ReportPath -Line "[OK] $($check.Name) = enabled"
        } else {
            Add-ReportLine -Path $ReportPath -Line "[WARN] $($check.Name) = $value, expected $($check.Expected)"
        }
    }
}

function Invoke-NCSWindowsLoggingSetup {
    param(
        [Parameter(Mandatory = $true)][string]$LogDir,
        [string]$ExternalScript = "",
        [switch]$VerifyOnly
    )

    $reportPath = Join-Path $LogDir "gpo-check.log"
    Set-Content -Path $reportPath -Value "NCS Windows audit/GPO verification - $(Get-Date -Format o)" -Encoding UTF8

    if ($ExternalScript -and (Test-Path -LiteralPath $ExternalScript)) {
        Add-ReportLine -Path $reportPath -Line "[INFO] External GPO script reference: $ExternalScript"
    } elseif ($ExternalScript) {
        Add-ReportLine -Path $reportPath -Line "[WARN] External GPO script not found: $ExternalScript"
    }

    if ($VerifyOnly) {
        Add-ReportLine -Path $reportPath -Line "[INFO] VerifyOnlyWindowsLogging is enabled. Local audit/PowerShell policy will not be changed."
    } else {
        Enable-NCSWindowsLoggingPolicy -ReportPath $reportPath
    }

    Test-NCSWindowsLoggingPolicy -ReportPath $reportPath
    Write-OK "GPO/audit verification report: $reportPath"
}

function Install-OrUpdate-Sysmon {
    param(
        [Parameter(Mandatory = $true)][string]$SysmonExe,
        [Parameter(Mandatory = $true)][string]$SysmonConfig
    )

    if (-not (Test-Path -LiteralPath $SysmonExe)) {
        throw "Sysmon64.exe not found: $SysmonExe"
    }
    if (-not (Test-Path -LiteralPath $SysmonConfig)) {
        throw "Sysmon config not found: $SysmonConfig"
    }

    $svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
    if (-not $svc) {
        $svc = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
    }

    if ($svc) {
        Write-Info "Sysmon service exists. Updating config using $SysmonConfig"
        & $SysmonExe -accepteula -c $SysmonConfig | Out-Null
    } else {
        Write-Info "Installing Sysmon64 using $SysmonConfig"
        & $SysmonExe -accepteula -i $SysmonConfig | Out-Null
    }

    try {
        & wevtutil.exe sl "Microsoft-Windows-Sysmon/Operational" /e:true /ms:524288000 | Out-Null
    } catch {
        Write-Warn "Could not enable/resize Sysmon channel: $($_.Exception.Message)"
    }

    $svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
    if (-not $svc) {
        $svc = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
    }
    if (-not $svc) {
        throw "Sysmon service was not found after install/update."
    }

    $channel = Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational" -ErrorAction Stop
    Write-OK "Sysmon service: $($svc.Name) status=$($svc.Status)"
    Write-OK "Sysmon channel readable: $($channel.LogName)"
}

function Test-LocalState {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedFilebeatPath
    )

    $results = New-Object System.Collections.Generic.List[object]

    $agentService = Get-ElasticAgentService
    $results.Add([PSCustomObject]@{
        Check = "Elastic Agent service"
        Result = if ($agentService -and $agentService.Status -eq "Running") { "OK" } else { "FAIL" }
        Detail = if ($agentService) { "name=$($agentService.Name) status=$($agentService.Status)" } else { "service not found" }
    })

    $sysmonService = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
    if (-not $sysmonService) {
        $sysmonService = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
    }
    $results.Add([PSCustomObject]@{
        Check = "Sysmon service"
        Result = if ($sysmonService -and $sysmonService.Status -eq "Running") { "OK" } else { "FAIL" }
        Detail = if ($sysmonService) { "name=$($sysmonService.Name) status=$($sysmonService.Status)" } else { "service not found" }
    })

    $filebeatProcess = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -like "*filebeat*" -or
            $_.CommandLine -like "*filebeat*" -or
            $_.CommandLine -like "*testbeat*"
        } |
        Select-Object -First 1
    $results.Add([PSCustomObject]@{
        Check = "Filebeat PQC child"
        Result = if ($filebeatProcess -and $filebeatProcess.CommandLine -like "*filebeat-pqc-windows-amd64.exe*") { "OK" } else { "FAIL" }
        Detail = if ($filebeatProcess) { "pid=$($filebeatProcess.ProcessId) name=$($filebeatProcess.Name)" } else { "process not found" }
    })

    foreach ($channel in Get-NCSWindowsEventChannels) {
        try {
            $logInfo = Get-WinEvent -ListLog $channel.Name -ErrorAction Stop
            $results.Add([PSCustomObject]@{
                Check = "Channel $($channel.Name)"
                Result = if ($logInfo.IsEnabled) { "OK" } else { "WARN" }
                Detail = "enabled=$($logInfo.IsEnabled) records=$($logInfo.RecordCount)"
            })
        } catch {
            $results.Add([PSCustomObject]@{
                Check = "Channel $($channel.Name)"
                Result = "FAIL"
                Detail = $_.Exception.Message
            })
        }
    }

    $expectedEnv = @{
        "PQC_FILEBEAT_BIN" = $ExpectedFilebeatPath
        "LOGSTASH_TLS_CURVE_TYPES" = "X25519MLKEM768"
        "LOGSTASH_TLS_MIN_VERSION" = "1.3"
        "LOGSTASH_TLS_STRICT_PQC" = "true"
    }

    foreach ($entry in $expectedEnv.GetEnumerator()) {
        $machineValue = [Environment]::GetEnvironmentVariable($entry.Key, "Machine")
        $results.Add([PSCustomObject]@{
            Check = "Machine env $($entry.Key)"
            Result = if ($machineValue -eq $entry.Value) { "OK" } else { "FAIL" }
            Detail = if ($machineValue) { "configured" } else { "missing" }
        })
    }

    $markerCount = 0
    $agentLogRoot = "C:\Program Files\Elastic\Agent\data"
    if (Test-Path -LiteralPath $agentLogRoot) {
        $markers = Get-ChildItem $agentLogRoot -Filter "*.ndjson" -Recurse -ErrorAction SilentlyContinue |
            Select-String -Pattern "TLS handshake completed|configured_curve_preferences|pqc_mode|strict_pqc|using_custom_filebeat|pqc_env_forwarded" -ErrorAction SilentlyContinue |
            Select-Object -Last 8
        $markerCount = @($markers).Count
        if ($markerCount -gt 0) {
            Write-Host ""
            Write-Host "Recent TLS/PQC markers:" -ForegroundColor Cyan
            $markers | ForEach-Object { Write-Host "  $($_.Line)" }
        }
    }
    $results.Add([PSCustomObject]@{
        Check = "Agent/Filebeat TLS/PQC markers"
        Result = if ($markerCount -gt 0) { "OK" } else { "WARN" }
        Detail = if ($markerCount -gt 0) { "markers_found=$markerCount" } else { "not seen yet; Agent may still be connecting" }
    })

    Write-Host ""
    Write-Host "Local verification summary:" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
}

Assert-Administrator
Assert-WindowsX64

$installRootFull = [System.IO.Path]::GetFullPath($InstallRoot)
$packagesDir = Join-Path $installRootFull "packages"
$agentDir = Join-Path $installRootFull "agent"
$filebeatDir = Join-Path $installRootFull "filebeat"
$logsDir = Join-Path $installRootFull "logs"
$resourceRoot = Get-ResourceRoot
$logstashHost = "${GatewayHost}:${GatewayPort}"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  NCS Elastic Agent PQC Windows Installer" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

Write-Phase "[0/9] Preflight"
New-Item -ItemType Directory -Force -Path @($packagesDir, $agentDir, $filebeatDir, $logsDir) | Out-Null
Write-Info "Install root: $installRootFull"
Write-Info "PQC Gateway: $logstashHost"
Test-TcpPort -HostName $GatewayHost -Port $GatewayPort -AllowOffline:$AllowGatewayOffline

Write-Phase "[1/9] Remove existing Elastic Agent"
Uninstall-ExistingElasticAgent

Write-Phase "[2/9] Download or use local PQC artifacts"
$agentZipPath = Join-Path $packagesDir $AgentZipNames[0]
$filebeatZipPath = Join-Path $packagesDir $FilebeatZipNames[0]
$manifestPath = Join-Path $packagesDir $ManifestName
$sha256Path = Join-Path $packagesDir $Sha256Name

Try-PrepareMetadataFile -Name $ManifestName -Destination $manifestPath | Out-Null
Try-PrepareMetadataFile -Name $Sha256Name -Destination $sha256Path | Out-Null
Show-ManifestInfo -ManifestPath $manifestPath

Copy-OrDownloadArtifact -Names $AgentZipNames -Destination $agentZipPath -ExplicitPath $AgentPackageZip
Copy-OrDownloadArtifact -Names $FilebeatZipNames -Destination $filebeatZipPath -ExplicitPath $FilebeatPqcZip

$shaMap = Get-Sha256Map -Path $sha256Path
Test-ArtifactHash -Path $agentZipPath -ShaMap $shaMap -CandidateNames $AgentZipNames
Test-ArtifactHash -Path $filebeatZipPath -ShaMap $shaMap -CandidateNames $FilebeatZipNames

Write-Phase "[3/9] Extract PQC artifacts"
if (Test-Path -LiteralPath $agentDir) { Remove-Item -LiteralPath $agentDir -Recurse -Force }
if (Test-Path -LiteralPath $filebeatDir) { Remove-Item -LiteralPath $filebeatDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path @($agentDir, $filebeatDir) | Out-Null
Expand-Archive -LiteralPath $agentZipPath -DestinationPath $agentDir -Force
Expand-Archive -LiteralPath $filebeatZipPath -DestinationPath $filebeatDir -Force
$elasticAgentExe = Resolve-ExtractedFile -Root $agentDir -Names @("elastic-agent.exe", "elastic-agent-pqc-windows-amd64.exe", "elastic-agent-pqc-phase1c-windows-amd64.exe")
$filebeatPqcExe = Resolve-ExtractedFile -Root $filebeatDir -Names @("filebeat-pqc-windows-amd64.exe", "filebeat.exe")
if (-not $elasticAgentExe) { throw "Elastic Agent binary not found after extraction." }
if (-not $filebeatPqcExe) { throw "Filebeat PQC binary not found after extraction." }
Write-OK "Elastic Agent binary: $elasticAgentExe"
Write-OK "Filebeat PQC binary: $filebeatPqcExe"

Write-Phase "[4/9] Install or update Sysmon"
$sysmonExe = Join-Path $resourceRoot "Sysmonv14\Sysmon64.exe"
$sysmonConfig = Join-Path $resourceRoot "Sysmonv14\sysmonconfig_Server.xml"
Install-OrUpdate-Sysmon -SysmonExe $sysmonExe -SysmonConfig $sysmonConfig

Write-Phase "[5/9] Configure Windows log and audit policy"
if ($VerifyOnlyWindowsLogging) {
    Write-Warn "Verify-only mode enabled. Script will not change local audit/PowerShell logging policy."
} else {
    Write-Info "Applying local audit/PowerShell logging policy."
}
$bundledGpoCheck = Join-Path $resourceRoot "gpo\checkGPOconfig-v1.2.ps1"
$effectiveGpoCheck = if ($GpoCheckScript) { $GpoCheckScript } else { $bundledGpoCheck }
Invoke-NCSWindowsLoggingSetup -LogDir $logsDir -ExternalScript $effectiveGpoCheck -VerifyOnly:$VerifyOnlyWindowsLogging

Write-Phase "[6/9] Create Elastic Agent standalone config"
$elasticAgentExe = Ensure-AgentPackageLayout -AgentExe $elasticAgentExe -FilebeatPqcExe $filebeatPqcExe
Write-StandaloneConfig -ConfigPath (Join-Path (Split-Path -Parent $elasticAgentExe) "elastic-agent.yml") -LogstashHost $logstashHost

Write-Phase "[7/9] Set Machine-level PQC environment"
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

Write-Phase "[8/9] Install Elastic Agent service"
Write-Info "Running Elastic Agent install in standalone mode. No Fleet URL/token is used."
& $elasticAgentExe install --force --non-interactive
Start-Sleep -Seconds 10

Write-Phase "[9/9] Verify local"
Test-LocalState -ExpectedFilebeatPath $filebeatPqcExe

Write-Host ""
Write-Host "NCS Elastic Agent PQC Windows install flow completed." -ForegroundColor Green
