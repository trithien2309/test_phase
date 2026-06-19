param(
    [string]$Repository = "trithien2309/test_phase",
    [string]$Branch = "demo",
    [string]$Tag = "linux-pqc-phase1-v1",
    [string]$ArtifactDir
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Require-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file not found: $Path"
    }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "..\.."))
if (-not $ArtifactDir) {
    $ArtifactDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "..\linux-pqc-build"))
} else {
    $ArtifactDir = [System.IO.Path]::GetFullPath($ArtifactDir)
}

$AgentArtifact = Join-Path $ArtifactDir "ncs-elastic-agent-pqc-linux-amd64.tar.gz"
$FilebeatArtifact = Join-Path $ArtifactDir "filebeat-pqc-linux-amd64.zip"
$GeneratedSums = Join-Path $ArtifactDir "SHA256SUMS.txt"
$ExpectedSums = Join-Path $RepoRoot "client\linux\packages\SHA256SUMS.txt"

Require-Command git
Require-Command gh
Require-File $AgentArtifact
Require-File $FilebeatArtifact
Require-File $GeneratedSums
Require-File $ExpectedSums

Write-Host "[1/5] Verify GitHub authentication"
& gh auth status
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

Write-Host "[2/5] Verify artifact SHA256"
$expected = @{}
Get-Content -LiteralPath $ExpectedSums | ForEach-Object {
    if ($_ -match '^([0-9A-Fa-f]{64})\s+(.+)$') {
        $expected[$Matches[2].Trim()] = $Matches[1].ToUpperInvariant()
    }
}

foreach ($artifact in @($AgentArtifact, $FilebeatArtifact)) {
    $name = Split-Path -Leaf $artifact
    if (-not $expected.ContainsKey($name)) {
        throw "No expected SHA256 for $name"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToUpperInvariant()
    if ($actual -ne $expected[$name]) {
        throw "SHA256 mismatch for $name. expected=$($expected[$name]) actual=$actual"
    }
    Write-Host "  [OK] $name"
}

Write-Host "[3/5] Verify branch and clean worktree"
Push-Location $RepoRoot
try {
    $currentBranch = (& git branch --show-current).Trim()
    if ($currentBranch -ne $Branch) {
        throw "Expected branch $Branch, current branch is $currentBranch"
    }
    if (& git status --porcelain) {
        throw "Git worktree is not clean. Commit or stash changes before publishing."
    }

    Write-Host "[4/5] Push $Branch"
    & git push origin $Branch
    if ($LASTEXITCODE -ne 0) {
        throw "git push failed"
    }

    Write-Host "[5/5] Create or update GitHub Release $Tag"
    & gh release view $Tag --repo $Repository *> $null
    if ($LASTEXITCODE -eq 0) {
        & gh release upload $Tag $AgentArtifact $FilebeatArtifact $GeneratedSums --clobber --repo $Repository
    } else {
        & gh release create $Tag $AgentArtifact $FilebeatArtifact $GeneratedSums `
            --repo $Repository `
            --target $Branch `
            --title "Linux PQC Phase 1 v1" `
            --notes "Custom Elastic Agent and Filebeat for Ubuntu standalone TLS 1.3 + X25519MLKEM768 testing."
    }
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub Release publish failed"
    }
} finally {
    Pop-Location
}

Write-Host "[OK] Release published: https://github.com/$Repository/releases/tag/$Tag"
