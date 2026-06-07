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

$scriptPath = Join-Path $PSScriptRoot "client\windows\elastic-agent-ncs-standalone-install.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Installer implementation not found: $scriptPath"
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
