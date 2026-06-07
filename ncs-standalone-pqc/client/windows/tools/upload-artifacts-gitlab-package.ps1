param(
    [Parameter(Mandatory = $true)]
    [string]$PrivateToken,

    [string]$GitLabBaseUrl = "https://git.ncs.io.vn",

    [string]$ProjectPath = "thien.nguyen/soc-sme",

    [string]$PackageName = "soc-sme-pqc",

    [string]$PackageVersion = "phase1-windows",

    [string]$PackagesDir = ""
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

if (-not $PackagesDir) {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $clientPackagesDir = Resolve-Path (Join-Path $scriptDir "..\packages") -ErrorAction SilentlyContinue
    $repoPackagesDir = Resolve-Path (Join-Path $scriptDir "..\..\..\packages") -ErrorAction SilentlyContinue
    if ($repoPackagesDir -and (
        (Test-Path -LiteralPath (Join-Path $repoPackagesDir.Path "ncs-elastic-agent-pqc-windows-amd64.zip")) -or
        (Test-Path -LiteralPath (Join-Path $repoPackagesDir.Path "elastic-agent-pqc-phase1c-windows-amd64-package.zip"))
    )) {
        $PackagesDir = $repoPackagesDir.Path
    } elseif ($clientPackagesDir) {
        $PackagesDir = $clientPackagesDir.Path
    } else {
        throw "Could not resolve a packages directory. Pass -PackagesDir explicitly."
    }
}

$artifactSpecs = @(
    @{
        UploadName = "ncs-elastic-agent-pqc-windows-amd64.zip"
        SourceNames = @("ncs-elastic-agent-pqc-windows-amd64.zip", "elastic-agent-pqc-phase1c-windows-amd64-package.zip")
        Required = $true
    },
    @{
        UploadName = "filebeat-pqc-windows-amd64.zip"
        SourceNames = @("filebeat-pqc-windows-amd64.zip")
        Required = $true
    },
    @{
        UploadName = "manifest.json"
        SourceNames = @("manifest.json")
        Required = $false
    },
    @{
        UploadName = "SHA256SUMS.txt"
        SourceNames = @("SHA256SUMS.txt")
        Required = $false
    }
)

function Resolve-UploadArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $path = Join-Path $Directory $name
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    foreach ($name in $Names) {
        $chunks = Get-ChildItem -LiteralPath $Directory -Filter "$name.part*" -File -ErrorAction SilentlyContinue |
            Sort-Object Name
        if (-not $chunks -or $chunks.Count -eq 0) {
            continue
        }

        $tempPath = Join-Path $env:TEMP $name
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }

        Write-Info "Reassembling $name from $($chunks.Count) chunks for upload"
        $out = [System.IO.File]::Open($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        try {
            foreach ($chunk in $chunks) {
                $in = [System.IO.File]::OpenRead($chunk.FullName)
                try {
                    $in.CopyTo($out)
                } finally {
                    $in.Dispose()
                }
            }
        } finally {
            $out.Dispose()
        }

        return $tempPath
    }

    return ""
}

$encodedProject = [System.Uri]::EscapeDataString($ProjectPath)
$headers = @{ "PRIVATE-TOKEN" = $PrivateToken }

foreach ($spec in $artifactSpecs) {
    $name = $spec.UploadName
    $path = Resolve-UploadArtifact -Directory $PackagesDir -Names $spec.SourceNames
    if (-not $path) {
        if ($spec.Required) {
            Write-Fail "Missing artifact or chunks for upload target: $name"
            throw "Artifact not found: $name"
        }
        Write-Info "Optional metadata not found, skipping: $name"
        continue
    }

    $uri = "$($GitLabBaseUrl.TrimEnd('/'))/api/v4/projects/$encodedProject/packages/generic/$PackageName/$PackageVersion/$name"
    Write-Info "Uploading $name"
    Write-Info "Target: $uri"
    Invoke-WebRequest -Method Put -Uri $uri -Headers $headers -InFile $path -ContentType "application/octet-stream" -UseBasicParsing | Out-Null
    Write-OK "Uploaded $name"
}

Write-Host ""
Write-OK "GitLab Generic Package Registry upload completed."
Write-Host "Download base URL:"
Write-Host "$($GitLabBaseUrl.TrimEnd('/'))/api/v4/projects/$encodedProject/packages/generic/$PackageName/$PackageVersion"
