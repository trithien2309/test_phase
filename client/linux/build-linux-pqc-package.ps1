param(
    [string]$SourceRoot,
    [string]$OutputDir,
    [string]$Version,
    [string]$Commit,
    [string]$AgentBinary,
    [string]$FilebeatBinary,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Require-File {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw $Message
    }
}

function Get-DefaultVersion {
    param([string]$Root)
    $versionFile = Join-Path $Root "version\version.go"
    if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
        throw "Cannot detect Elastic Agent version: $versionFile is missing"
    }
    $match = Select-String -LiteralPath $versionFile -Pattern 'const defaultBeatVersion = "([^"]+)"' | Select-Object -First 1
    if ($match -and $match.Matches.Count -gt 0) {
        return $match.Matches[0].Groups[1].Value
    }
    throw "Cannot detect defaultBeatVersion from $versionFile"
}

function Get-DefaultCommit {
    param([string]$Root)
    try {
        $output = & git.exe -c "safe.directory=$Root" -C $Root rev-parse --short=12 HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            return ([string]($output | Select-Object -First 1)).Trim()
        }
    } catch {
    }
    return ""
}

if (-not $SourceRoot) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $SourceRoot = Resolve-FullPath (Join-Path $ScriptDir "..\..\..\..")
} else {
    $SourceRoot = Resolve-FullPath $SourceRoot
}

Require-File (Join-Path $SourceRoot "go.mod") "Elastic Agent source root not found: $SourceRoot"

if (-not $OutputDir) {
    $OutputDir = Join-Path $SourceRoot "publish\linux-pqc-build"
}
$OutputDir = Resolve-FullPath $OutputDir

if (-not $Version) {
    $Version = Get-DefaultVersion -Root $SourceRoot
}
if (-not $Commit) {
    $Commit = Get-DefaultCommit -Root $SourceRoot
}
if (-not $Commit -or $Commit -eq "unknown" -or $Commit -eq "pqcdev") {
    throw "A real source commit is required. Run from a Git checkout or pass -Commit explicitly."
}

$BuildDir = Join-Path $OutputDir "build\linux-amd64"
$PackageDir = Join-Path $OutputDir "package"
$PackageRoot = Join-Path $PackageDir "ncs-elastic-agent-pqc-linux-amd64"
$VersionedHome = "data/elastic-agent-$Version-$Commit"
$VersionedHomePath = Join-Path $PackageRoot $VersionedHome
$ComponentsDir = Join-Path $VersionedHomePath "components"
$AgentOut = Join-Path $BuildDir "elastic-agent-pqc-linux-amd64"
$FilebeatOut = Join-Path $BuildDir "filebeat-pqc-linux-amd64"
$PackageOut = Join-Path $OutputDir "ncs-elastic-agent-pqc-linux-amd64.tar.gz"
$FilebeatZipOut = Join-Path $OutputDir "filebeat-pqc-linux-amd64.zip"
$ShaOut = Join-Path $OutputDir "SHA256SUMS.txt"

Write-Host "[INFO] Source root: $SourceRoot"
Write-Host "[INFO] Output dir: $OutputDir"
Write-Host "[INFO] Version: $Version"
Write-Host "[INFO] Commit/hash: $Commit"

New-Item -ItemType Directory -Force -Path $BuildDir, $OutputDir | Out-Null

if (-not $SkipBuild) {
    Write-Host "[1/4] Building custom Elastic Agent Linux binary"
    Push-Location $SourceRoot
    try {
        $env:GOOS = "linux"
        $env:GOARCH = "amd64"
        $env:CGO_ENABLED = "0"
        & go build -ldflags "-X github.com/elastic/elastic-agent/version.commit=$Commit" -o $AgentOut .
        if ($LASTEXITCODE -ne 0) {
            throw "Elastic Agent build failed"
        }
    } finally {
        Pop-Location
    }

    Write-Host "[2/4] Building custom Filebeat PQC Linux binary"
    Push-Location (Join-Path $SourceRoot "beats")
    try {
        $env:GOOS = "linux"
        $env:GOARCH = "amd64"
        $env:CGO_ENABLED = "0"
        & go build -o $FilebeatOut .\x-pack\filebeat
        if ($LASTEXITCODE -ne 0) {
            throw "Filebeat PQC build failed"
        }
    } finally {
        Pop-Location
    }
} else {
    Require-File $AgentBinary "--skip-build requires -AgentBinary"
    Require-File $FilebeatBinary "--skip-build requires -FilebeatBinary"
    if ((Resolve-FullPath $AgentBinary) -ne (Resolve-FullPath $AgentOut)) {
        Copy-Item -LiteralPath $AgentBinary -Destination $AgentOut -Force
    }
    if ((Resolve-FullPath $FilebeatBinary) -ne (Resolve-FullPath $FilebeatOut)) {
        Copy-Item -LiteralPath $FilebeatBinary -Destination $FilebeatOut -Force
    }
}

Write-Host "[3/4] Creating custom Agent package layout"
if (Test-Path -LiteralPath $PackageRoot) {
    Remove-Item -LiteralPath $PackageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $ComponentsDir | Out-Null

Copy-Item -LiteralPath $AgentOut -Destination (Join-Path $PackageRoot "elastic-agent") -Force
Copy-Item -LiteralPath $AgentOut -Destination (Join-Path $VersionedHomePath "elastic-agent") -Force
Copy-Item -LiteralPath $FilebeatOut -Destination (Join-Path $ComponentsDir "testbeat") -Force

Set-Content -LiteralPath (Join-Path $PackageRoot "package.version") -Value $Version -NoNewline
Set-Content -LiteralPath (Join-Path $VersionedHomePath "package.version") -Value $Version -NoNewline

$spec = @'
version: 2
inputs:
  - name: filestream
    description: "Filestream"
    platforms: &platforms
      - linux/amd64
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
'@
Set-Content -LiteralPath (Join-Path $ComponentsDir "testbeat.spec.yml") -Value $spec

$manifest = @"
version: co.elastic.agent/v1
kind: PackageManifest
package:
  version: $Version
  snapshot: false
  hash: $Commit
  versioned-home: $VersionedHome
  flavors:
    basic:
      - testbeat
    servers:
      - testbeat
  path-mappings:
    - ${VersionedHome}: ${VersionedHome}
      manifest.yaml: ${VersionedHome}/manifest.yaml
"@
Set-Content -LiteralPath (Join-Path $PackageRoot "manifest.yaml") -Value $manifest
Copy-Item -LiteralPath (Join-Path $PackageRoot "manifest.yaml") -Destination (Join-Path $VersionedHomePath "manifest.yaml") -Force

Write-Host "[4/4] Writing archives"
if (Test-Path -LiteralPath $PackageOut) {
    Remove-Item -LiteralPath $PackageOut -Force
}
Push-Location $PackageDir
try {
    & tar -czf $PackageOut "ncs-elastic-agent-pqc-linux-amd64"
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed for Agent package"
    }
} finally {
    Pop-Location
}

if (Test-Path -LiteralPath $FilebeatZipOut) {
    Remove-Item -LiteralPath $FilebeatZipOut -Force
}
Compress-Archive -LiteralPath $FilebeatOut -DestinationPath $FilebeatZipOut -Force

$hashLines = @()
foreach ($artifact in @($PackageOut, $FilebeatZipOut)) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToUpperInvariant()
    $hashLines += "$hash  $(Split-Path -Leaf $artifact)"
}
Set-Content -LiteralPath $ShaOut -Value $hashLines

Write-Host "[OK] Package: $PackageOut"
Write-Host "[OK] Filebeat artifact: $FilebeatZipOut"
Write-Host "[OK] SHA256: $ShaOut"
