[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$ToolPath = Join-Path $RepoRoot 'tools\Get-GammaArenaReleaseNotes.ps1'
if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
    throw 'Release notes extractor is missing'
}
$VersionExpanderPath = Join-Path $RepoRoot 'tools\Expand-GammaArenaVersion.ps1'
if (-not (Test-Path -LiteralPath $VersionExpanderPath -PathType Leaf)) {
    throw 'Runtime version expander is missing'
}

$VersionMarker = '@GAMMA_ARENA_VERSION@'
$RepositoryVersionPath = Join-Path $RepoRoot 'VERSION'
$RepositoryVersion = ([IO.File]::ReadAllText($RepositoryVersionPath)).Trim()
if ($RepositoryVersion -notmatch '^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') {
    throw 'Repository VERSION is not a plain SemVer triplet'
}

$MigrationPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_migrations.script'
$MigrationSource = [IO.File]::ReadAllText($MigrationPath)
if ([regex]::Matches($MigrationSource, [regex]::Escape($VersionMarker)).Count -ne 1) {
    throw 'Runtime migration source must contain exactly one version marker'
}
if ($MigrationSource.Contains('CURRENT_ADDON_VERSION = "' + $RepositoryVersion + '"')) {
    throw 'Runtime migration source duplicates VERSION'
}

$BuildPath = Join-Path $RepoRoot 'tools\Build-GammaArena.ps1'
$BuildSource = [IO.File]::ReadAllText($BuildPath)
$RuntimeCopyIndex = $BuildSource.IndexOf('Copy-GameDataTree (Join-Path $RepoRoot ''src\gamedata'') $StageGameData')
$RuntimeExpandIndex = $BuildSource.IndexOf('& (Join-Path $RepoRoot ''tools\Expand-GammaArenaVersion.ps1'') -Path $RuntimeVersionPath -Version $Version')
if ($RuntimeCopyIndex -lt 0 -or $RuntimeExpandIndex -le $RuntimeCopyIndex) {
    throw 'Release build does not expand the runtime version from VERSION'
}

$CompatibilitySchemaPath = Join-Path $RepoRoot 'schemas\compatibility-manifest-v1.md'
$CompatibilitySchema = [IO.File]::ReadAllText($CompatibilitySchemaPath)
$AddonVersionRow = [regex]::Match($CompatibilitySchema, '(?m)^\| `addon_version` \|[^\r\n]+$').Value
if ($AddonVersionRow -notmatch 'repository `VERSION`' -or $AddonVersionRow -match '"\d+\.\d+\.\d+"') {
    throw 'Compatibility schema duplicates the current add-on version'
}

$ProjectTestPath = Join-Path $RepoRoot 'tests\static\Test-Project.ps1'
$ProjectTestSource = [IO.File]::ReadAllText($ProjectTestPath)
if ($ProjectTestSource -match "AddonVersion\s+-ceq\s+'\d+\.\d+\.\d+'") {
    throw 'Static project contract pins a concrete release version'
}

function Write-Utf8([string]$Path, [string]$Text) {
    $Parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Assert-Fails([scriptblock]$Action, [string]$Pattern) {
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw
        }
        return
    }
    throw "Expected failure matching: $Pattern"
}

function Join-Lf([string[]]$Lines) {
    return [string]::Join("`n", $Lines)
}

$Fixture = Join-Path ([IO.Path]::GetTempPath()) ('gamma-arena-release-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $Fixture -Force | Out-Null
    $VersionPath = Join-Path $Fixture 'VERSION'
    $ChangelogPath = Join-Path $Fixture 'CHANGELOG.md'
    $OutputPath = Join-Path $Fixture 'build\release-notes.md'
    $RuntimePath = Join-Path $Fixture 'gamma_arena_migrations.script'

    $RuntimeTemplate = 'local CURRENT_ADDON_VERSION = "' + $VersionMarker + '"' + "`n"
    Write-Utf8 $RuntimePath $RuntimeTemplate
    & $VersionExpanderPath -Path $RuntimePath -Version '1.2.3'
    $RuntimeBytes = [IO.File]::ReadAllBytes($RuntimePath)
    if ($RuntimeBytes.Length -ge 3 -and $RuntimeBytes[0] -eq 0xEF -and $RuntimeBytes[1] -eq 0xBB -and $RuntimeBytes[2] -eq 0xBF) {
        throw 'Expanded runtime version contains a UTF-8 BOM'
    }
    $ExpandedRuntime = [Text.Encoding]::UTF8.GetString($RuntimeBytes)
    $ExpectedRuntime = 'local CURRENT_ADDON_VERSION = "1.2.3"' + "`n"
    if ($ExpandedRuntime -cne $ExpectedRuntime) {
        throw 'Runtime version expansion is incorrect'
    }

    foreach ($FailureCase in @(
        [PSCustomObject]@{ Content = $RuntimeTemplate; Version = 'v1.2.3'; Pattern = 'SemVer' },
        [PSCustomObject]@{ Content = $ExpectedRuntime; Version = '1.2.3'; Pattern = 'exactly one' },
        [PSCustomObject]@{ Content = $RuntimeTemplate + $RuntimeTemplate; Version = '1.2.3'; Pattern = 'exactly one' }
    )) {
        Write-Utf8 $RuntimePath $FailureCase.Content
        Assert-Fails { & $VersionExpanderPath -Path $RuntimePath -Version $FailureCase.Version } $FailureCase.Pattern
        if ([IO.File]::ReadAllText($RuntimePath) -cne $FailureCase.Content) {
            throw 'Runtime version validation failure changed the source file'
        }
    }

    Write-Utf8 $VersionPath "1.2.3`n"
    Write-Utf8 $ChangelogPath (Join-Lf @(
        '# Changelog',
        '',
        '## Unreleased',
        '',
        '- Next',
        '',
        '## 1.2.3 - 2026-08-29',
        '',
        '- First',
        '- Second `code`',
        '',
        '## 1.2.2 - 2026-08-20',
        '',
        '- Old',
        ''
    ))

    & $ToolPath -RepoRoot $Fixture -Tag 'v1.2.3' -OutputPath $OutputPath
    $Bytes = [IO.File]::ReadAllBytes($OutputPath)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        throw 'Release notes contain a UTF-8 BOM'
    }
    $Notes = [Text.Encoding]::UTF8.GetString($Bytes)
    $ExpectedNotes = Join-Lf @('- First', '- Second `code`', '')
    if ($Notes -cne $ExpectedNotes) {
        throw 'Release notes body is incorrect'
    }
    if ($Notes.Contains("`r") -or $Notes.Contains('- Old') -or $Notes.Contains('- Next')) {
        throw 'Release notes boundaries are incorrect'
    }

    Write-Utf8 $OutputPath 'sentinel'
    Assert-Fails { & $ToolPath -RepoRoot $Fixture -Tag '1.2.3' -OutputPath $OutputPath } 'tag'
    if ([IO.File]::ReadAllText($OutputPath) -cne 'sentinel') {
        throw 'Validation failure changed the output'
    }

    Assert-Fails { & $ToolPath -RepoRoot $Fixture -Tag 'v1.2.4' -OutputPath $OutputPath } 'VERSION'
    Assert-Fails { & $ToolPath -RepoRoot $Fixture -Tag 'v01.2.3' -OutputPath $OutputPath } 'tag'

    $Cases = @(
        [PSCustomObject]@{
            Text = Join-Lf @('# Changelog', '', '## 1.2.2 - 2026-08-20', '', '- Old', '')
            Pattern = 'missing'
        },
        [PSCustomObject]@{
            Text = Join-Lf @('# Changelog', '', '## 1.2.3 - 2026-08-29', '', '- One', '', '## 1.2.3 - 2026-08-28', '', '- Two', '')
            Pattern = 'exactly one'
        },
        [PSCustomObject]@{
            Text = Join-Lf @('# Changelog', '', '## 1.2.3 - someday', '', '- Entry', '')
            Pattern = 'malformed'
        },
        [PSCustomObject]@{
            Text = Join-Lf @('# Changelog', '', '## 1.2.3 - 2026-02-30', '', '- Entry', '')
            Pattern = 'malformed'
        },
        [PSCustomObject]@{
            Text = Join-Lf @('# Changelog', '', '## 1.2.3 - 2026-08-29', '', '## 1.2.2 - 2026-08-20', '', '- Old', '')
            Pattern = 'empty'
        }
    )
    foreach ($Case in $Cases) {
        Write-Utf8 $ChangelogPath $Case.Text
        Assert-Fails { & $ToolPath -RepoRoot $Fixture -Tag 'v1.2.3' -OutputPath $OutputPath } $Case.Pattern
    }
}
finally {
    if (Test-Path -LiteralPath $Fixture) {
        Remove-Item -LiteralPath $Fixture -Recurse -Force
    }
}

Write-Host 'PASS: release automation and runtime version expansion passed'
