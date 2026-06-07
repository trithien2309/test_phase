param(
    [string]$ArtifactBaseUrl = "https://github.com/trithien2309/test_phase/raw/main/siem-pqc-phase1c/packages",

    [string]$BootstrapBaseUrl = "https://github.com/trithien2309/test_phase/raw/main/ncs-standalone-pqc",

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

function Write-BootstrapInfo {
    param([string]$Message)
    Write-Host "  [BOOTSTRAP] $Message" -ForegroundColor Cyan
}

function Invoke-BootstrapDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Write-BootstrapInfo "Downloading $Uri"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
}

function Ensure-BootstrapPayload {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$BootstrapRoot
    )

    $requiredFiles = @(
        "client/windows/elastic-agent-ncs-standalone-install.ps1",
        "client/windows/packages/SHA256SUMS.txt",
        "client/windows/packages/manifest.json",
        "client/windows/resources/gpo/checkGPOconfig-v1.2.ps1",
        "client/windows/resources/gpo/Set_Audit_Pol_PS_v2_3_4_5_v2.cmd",
        "client/windows/resources/Sysmonv14/Eula.txt",
        "client/windows/resources/Sysmonv14/Sysmon64.exe",
        "client/windows/resources/Sysmonv14/sysmonconfig_Server.xml"
    )

    foreach ($relativePath in $requiredFiles) {
        $destination = Join-Path $BootstrapRoot ($relativePath -replace "/", "\")
        $uri = "$($BaseUrl.TrimEnd('/'))/$relativePath"
        Invoke-BootstrapDownload -Uri $uri -Destination $destination
    }
}

$scriptPath = Join-Path $PSScriptRoot "..\..\client\windows\elastic-agent-ncs-standalone-install.ps1"
$scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
if (-not (Test-Path -LiteralPath $scriptPath)) {
    $bootstrapRoot = Join-Path $InstallRoot "bootstrap"
    Write-BootstrapInfo "Local client/windows payload not found. Bootstrapping from GitHub into $bootstrapRoot"
    Ensure-BootstrapPayload -BaseUrl $BootstrapBaseUrl -BootstrapRoot $bootstrapRoot
    $scriptPath = Join-Path $bootstrapRoot "client\windows\elastic-agent-ncs-standalone-install.ps1"
}

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Installer implementation not found after bootstrap: $scriptPath"
}

& $scriptPath `
    -ArtifactBaseUrl $ArtifactBaseUrl `
    -ArtifactPrivateToken $ArtifactPrivateToken `
    -AgentPackageZip $AgentPackageZip `
    -FilebeatPqcZip $FilebeatPqcZip `
    -InstallRoot $InstallRoot `
    -GatewayHost $GatewayHost `
    -GatewayPort $GatewayPort `
    -GpoCheckScript $GpoCheckScript `
    -SmokeLogPath $SmokeLogPath `
    -AllowGatewayOffline:$AllowGatewayOffline `
    -VerifyOnlyWindowsLogging:$VerifyOnlyWindowsLogging
