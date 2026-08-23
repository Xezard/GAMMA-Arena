[CmdletBinding()]
param(
    [ValidateSet('Release', 'Dev')]
    [string]$Configuration = 'Release',
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ReleaseOutputDirectory = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'dist')).TrimEnd('\', '/')
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = $ReleaseOutputDirectory
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
if ($Configuration -eq 'Release' -and -not [string]::Equals($OutputDirectory, $ReleaseOutputDirectory, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Release output directory must be $ReleaseOutputDirectory"
}

& (Join-Path $RepoRoot 'tools\Test-GammaArena.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Static project checks failed; build aborted.'
}

$Version = (Get-Content -LiteralPath (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
$BuildRoot = Join-Path $RepoRoot 'build'
$StageRoot = Join-Path $BuildRoot ("staging-$Configuration")
$StageGameData = Join-Path $StageRoot 'gamedata'
$PackagePath = Join-Path $OutputDirectory ("Gamma-Arena-v$Version-MO2.zip")

if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $StageGameData -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Copy-GameDataTree([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }

    $Files = @(Get-ChildItem -LiteralPath $Source -File -Recurse | Where-Object { $_.Name -ne '.gitkeep' })
    foreach ($File in $Files) {
        $RelativePath = $File.FullName.Substring($Source.Length).TrimStart('\', '/')
        $DestinationPath = Join-Path $Destination $RelativePath
        $DestinationParent = Split-Path -Parent $DestinationPath
        New-Item -ItemType Directory -Path $DestinationParent -Force | Out-Null
        Copy-Item -LiteralPath $File.FullName -Destination $DestinationPath -Force
    }
}

Copy-GameDataTree (Join-Path $RepoRoot 'src\gamedata') $StageGameData
if ($Configuration -eq 'Dev') {
    Copy-GameDataTree (Join-Path $RepoRoot 'dev\gamedata') $StageGameData
}

Copy-Item -LiteralPath (Join-Path $RepoRoot 'README.md') -Destination (Join-Path $StageRoot 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'CHANGELOG.md') -Destination (Join-Path $StageRoot 'CHANGELOG.md') -Force

function Get-OrdinalSortedPaths([string]$Root) {
    $Paths = @([IO.Directory]::GetFiles($Root, '*', [IO.SearchOption]::AllDirectories))
    [Array]::Sort($Paths, [StringComparer]::Ordinal)
    return $Paths
}

function Get-ZipRelativePath([string]$Root, [string]$Path) {
    return $Path.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
}

$ManifestFiles = @()
foreach ($FilePath in (Get-OrdinalSortedPaths $StageRoot)) {
    $ManifestFiles += [ordered]@{
        path = Get-ZipRelativePath $StageRoot $FilePath
        sha256 = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash
    }
}

$Manifest = [ordered]@{
    addon_version = $Version
    state_schema_version = 1
    session_schema_version = 1
    fight_spec_schema_version = 4
    generator_version = 6
    catalog_revision = 6
    layout_revision = 2
    compatibility_manifest_version = 1
    files = $ManifestFiles
}
$ManifestPath = Join-Path $StageRoot 'gamma-arena-manifest.json'
$ManifestJson = (($Manifest | ConvertTo-Json -Depth 5) -replace "`r`n?", "`n")
[IO.File]::WriteAllText($ManifestPath, ($ManifestJson + "`n"), (New-Object Text.UTF8Encoding($false)))

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path -LiteralPath $PackagePath) {
    Remove-Item -LiteralPath $PackagePath -Force
}

$FixedTimestamp = [DateTimeOffset]::Parse('1980-01-01T00:00:00+00:00')
$Stream = [IO.File]::Open($PackagePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $Archive = New-Object IO.Compression.ZipArchive($Stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        [string[]]$ZipEntryPaths = @('gamedata/') + @((Get-OrdinalSortedPaths $StageRoot) | ForEach-Object { Get-ZipRelativePath $StageRoot $_ })
        [Array]::Sort($ZipEntryPaths, [StringComparer]::Ordinal)

        foreach ($ZipEntryPath in $ZipEntryPaths) {
            $Entry = $Archive.CreateEntry($ZipEntryPath, [IO.Compression.CompressionLevel]::Optimal)
            $Entry.LastWriteTime = $FixedTimestamp
            if ($ZipEntryPath -eq 'gamedata/') {
                continue
            }

            $FilePath = Join-Path $StageRoot $ZipEntryPath.Replace('/', '\')
            $Input = [IO.File]::OpenRead($FilePath)
            try {
                $Output = $Entry.Open()
                try {
                    $Input.CopyTo($Output)
                }
                finally {
                    $Output.Dispose()
                }
            }
            finally {
                $Input.Dispose()
            }
        }
    }
    finally {
        $Archive.Dispose()
    }
}
finally {
    $Stream.Dispose()
}

Write-Host "Built $PackagePath"
