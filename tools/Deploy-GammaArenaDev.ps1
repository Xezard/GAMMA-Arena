[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Mo2Root
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $Mo2Root -PathType Container)) {
    throw "MO2 root does not exist: $Mo2Root"
}

$ResolvedMo2Root = (Resolve-Path -LiteralPath $Mo2Root).Path.TrimEnd('\', '/')
$ModsDirectory = Join-Path $ResolvedMo2Root 'mods'
New-Item -ItemType Directory -Path $ModsDirectory -Force | Out-Null
$ModsItem = Get-Item -LiteralPath $ModsDirectory
if (-not $ModsItem.PSIsContainer -or (($ModsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw "MO2 mods directory must be a real directory: $ModsDirectory"
}
$ResolvedModsDirectory = (Resolve-Path -LiteralPath $ModsDirectory).Path.TrimEnd('\', '/')
$ExpectedTarget = [IO.Path]::GetFullPath((Join-Path $ResolvedModsDirectory 'Gamma Arena DEV')).TrimEnd('\', '/')
$TargetDirectory = $ExpectedTarget

if (-not [string]::Equals((Split-Path -Parent $TargetDirectory).TrimEnd('\', '/'), $ResolvedModsDirectory, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Deployment target does not equal <Mo2Root>\\mods\\Gamma Arena DEV.'
}

$ModsPrefix = $ResolvedModsDirectory + [IO.Path]::DirectorySeparatorChar
if (-not $TargetDirectory.StartsWith($ModsPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals($TargetDirectory, $ResolvedModsDirectory, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe deployment target: $TargetDirectory"
}

$DevOutputDirectory = Join-Path $RepoRoot 'build\dev-package'
& (Join-Path $RepoRoot 'tools\Build-GammaArena.ps1') -Configuration Dev -OutputDirectory $DevOutputDirectory
if ($LASTEXITCODE -ne 0) {
    throw 'Dev package build failed.'
}

$Version = (Get-Content -LiteralPath (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
$PackagePath = Join-Path $DevOutputDirectory ("Gamma-Arena-v$Version-MO2.zip")
$ExtractDirectory = Join-Path $RepoRoot 'build\dev-deploy-extract'
if (Test-Path -LiteralPath $ExtractDirectory) {
    Remove-Item -LiteralPath $ExtractDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $ExtractDirectory -Force | Out-Null
Expand-Archive -LiteralPath $PackagePath -DestinationPath $ExtractDirectory -Force

if (Test-Path -LiteralPath $TargetDirectory) {
    $TargetItem = Get-Item -LiteralPath $TargetDirectory -Force
    if (-not $TargetItem.PSIsContainer) {
        throw "Refusing non-directory deployment target: $TargetDirectory"
    }
    if (($TargetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing reparse-point deployment target: $TargetDirectory"
    }
    $ResolvedTarget = (Resolve-Path -LiteralPath $TargetDirectory).Path.TrimEnd('\', '/')
    if (-not [string]::Equals($ResolvedTarget, $ExpectedTarget, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe resolved deployment target: $ResolvedTarget"
    }
    Remove-Item -LiteralPath $ResolvedTarget -Recurse -Force
}

New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $ExtractDirectory -Force | Copy-Item -Destination $TargetDirectory -Recurse -Force
Write-Host "Deployed Gamma Arena DEV to $TargetDirectory"
