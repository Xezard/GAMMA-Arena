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

Write-Host 'PASS: release notes extraction passed'
