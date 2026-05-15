param(
    [Parameter(Mandatory = $true)]
    [string]$ElasticAgentExe,

    [Parameter(Mandatory = $true)]
    [string]$FilebeatPqcExe,

    [Parameter(Mandatory = $true)]
    [string]$FleetUrl,

    [Parameter(Mandatory = $true)]
    [string]$EnrollmentToken,

    [switch]$Insecure
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated Administrator PowerShell."
    }
}

function Get-AgentBuildInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentExe
    )

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
        Write-Warning "Could not read Elastic Agent binary version. Falling back to $version/$commit. Error: $($_.Exception.Message)"
    }

    $shortCommit = $commit
    if ($shortCommit.Length -gt 6) {
        $shortCommit = $shortCommit.Substring(0, 6)
    }

    return [PSCustomObject]@{
        Version = $version
        Commit = $commit
        ShortCommit = $shortCommit
        VersionedHome = "data\elastic-agent-$version-$shortCommit"
        VersionedHomeUnix = "data/elastic-agent-$version-$shortCommit"
    }
}

function Write-TestbeatSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

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
        Write-Host "Creating canonical package binary: $canonicalAgentExe"
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
        (Join-Path (Split-Path -Parent $PSCommandPath) "testbeat.spec.yml"),
        (Join-Path (Split-Path -Parent $PSCommandPath) "..\..\specs\testbeat.spec.yml")
    )
    $specSource = $specCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($specSource) {
        Copy-Item -LiteralPath $specSource -Destination $specDestination -Force
    } else {
        Write-Warning "testbeat.spec.yml was not found near the package or script. Writing a minimal Phase 1C spec for log/filestream/winlog."
        Write-TestbeatSpec -Path $specDestination
    }

    $packageVersion = Join-Path $agentDir "package.version"
    Set-Content -Path $packageVersion -Value $buildInfo.Version -Encoding ASCII

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

    Write-Host "Elastic Agent package layout is ready."
    Write-Host "Agent package dir: $agentDir"
    Write-Host "Versioned home: $versionedHome"
    Write-Host "Component binary placeholder: $(Join-Path $componentsDir 'testbeat.exe')"
    Write-Host "Component spec: $specDestination"

    return $AgentExe
}

Assert-Administrator

$ElasticAgentExe = (Resolve-Path $ElasticAgentExe).Path
$FilebeatPqcExe = (Resolve-Path $FilebeatPqcExe).Path
$ElasticAgentExe = Ensure-AgentPackageLayout -AgentExe $ElasticAgentExe -FilebeatPqcExe $FilebeatPqcExe

New-Item -ItemType Directory -Force C:\pqc-test | Out-Null
$TestLog = "C:\pqc-test\fleet-pqc-test.log"
$Padding = "A" * 1600
Set-Content -Path $TestLog -Value "fleet-pqc-bootstrap $(Get-Date -Format o) $Padding"
Add-Content -Path $TestLog -Value "fleet-pqc-ready $(Get-Date -Format o) $Padding"

$machineEnv = @{
    "PQC_FILEBEAT_BIN" = $FilebeatPqcExe
    "LOGSTASH_TLS_CURVE_TYPES" = "X25519MLKEM768"
    "LOGSTASH_TLS_MIN_VERSION" = "1.3"
    "LOGSTASH_TLS_STRICT_PQC" = "true"
}

foreach ($entry in $machineEnv.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Machine")
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
}

Write-Host "Machine-level PQC environment configured."
Write-Host "PQC_FILEBEAT_BIN=$FilebeatPqcExe"
Write-Host "LOGSTASH_TLS_CURVE_TYPES=$($env:LOGSTASH_TLS_CURVE_TYPES)"
Write-Host "LOGSTASH_TLS_MIN_VERSION=$($env:LOGSTASH_TLS_MIN_VERSION)"
Write-Host "LOGSTASH_TLS_STRICT_PQC=$($env:LOGSTASH_TLS_STRICT_PQC)"
Write-Host "Test log: $TestLog"

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

Write-Host "Installing and enrolling Elastic Agent. Enrollment token is intentionally not printed."
& $ElasticAgentExe @installArgs

Write-Host ""
Write-Host "Elastic Agent service:"
Get-Service elastic-agent | Format-Table -AutoSize

Write-Host ""
Write-Host "Check spawned Filebeat process with:"
Write-Host 'Get-CimInstance Win32_Process | Where-Object { $_.Name -like "*filebeat*" -or $_.CommandLine -like "*filebeat*" } | Select-Object ProcessId,CommandLine'

Write-Host ""
Write-Host "Append another test event with:"
Write-Host 'Add-Content C:\pqc-test\fleet-pqc-test.log "fleet-pqc-event $(Get-Date -Format o)"'
