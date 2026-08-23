[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$DocumentPath,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($DocumentPath)) {
    $DocumentPath = Join-Path $RepoRoot 'docs\arena-balance.md'
}

function Read-GammaArenaLtx([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Balance source is missing: $Path"
    }

    $Sections = [ordered]@{}
    $Current = $null
    $LineNumber = 0
    foreach ($RawLine in Get-Content -LiteralPath $Path) {
        $LineNumber++
        $Line = $RawLine.Trim()
        if ($Line.Length -eq 0 -or $Line.StartsWith(';') -or $Line.StartsWith('#')) {
            continue
        }
        if ($Line -match '^\[([^\]]+)\]$') {
            $Name = $Matches[1]
            if ($Sections.Contains($Name)) {
                throw "LTX duplicate section '$Name' at ${Path}:$LineNumber"
            }
            $Sections[$Name] = [ordered]@{}
            $Current = $Sections[$Name]
            continue
        }
        if ($null -eq $Current -or $Line -notmatch '^([^=]+?)\s*=\s*(.*?)\s*$') {
            throw "Malformed LTX line at ${Path}:$LineNumber"
        }
        $Key = $Matches[1].Trim()
        if ($Current.Contains($Key)) {
            throw "LTX duplicate key '$Key' at ${Path}:$LineNumber"
        }
        $Current[$Key] = $Matches[2]
    }
    return $Sections
}

function Get-RequiredLtxValue($Ltx, [string]$Section, [string]$Key, [string]$Path) {
    if (-not $Ltx.Contains($Section) -or -not $Ltx[$Section].Contains($Key)) {
        throw "Required LTX value [$Section] $Key is missing: $Path"
    }
    return [string]$Ltx[$Section][$Key]
}

function Get-RequiredLtxInt($Ltx, [string]$Section, [string]$Key, [string]$Path) {
    $Raw = Get-RequiredLtxValue $Ltx $Section $Key $Path
    $Value = 0
    if (-not [int]::TryParse(
        $Raw,
        [Globalization.NumberStyles]::Integer,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$Value
    )) {
        throw "Required integer [$Section] $Key is malformed: $Path"
    }
    return $Value
}

function Get-SubstringCount([string]$Text, [string]$Value) {
    $Count = 0
    $Offset = 0
    while (($Offset = $Text.IndexOf($Value, $Offset, [StringComparison]::Ordinal)) -ge 0) {
        $Count++
        $Offset += $Value.Length
    }
    return $Count
}

function Set-GeneratedMarkdownBlocks([string]$Document, $Blocks) {
    $Result = $Document.Replace("`r`n", "`n").Replace("`r", "`n")
    foreach ($Name in $Blocks.Keys) {
        $Begin = "<!-- BEGIN GENERATED: $Name -->"
        $End = "<!-- END GENERATED: $Name -->"
        if ((Get-SubstringCount $Result $Begin) -ne 1 -or (Get-SubstringCount $Result $End) -ne 1) {
            throw "Generated block markers must exist exactly once: $Name"
        }
        $BeginIndex = $Result.IndexOf($Begin, [StringComparison]::Ordinal)
        $EndIndex = $Result.IndexOf($End, [StringComparison]::Ordinal)
        if ($EndIndex -le $BeginIndex) {
            throw "Generated block markers are reversed: $Name"
        }
        $Before = $Result.Substring(0, $BeginIndex + $Begin.Length)
        $After = $Result.Substring($EndIndex)
        $Body = ([string]$Blocks[$Name]).Trim("`r", "`n")
        $Result = $Before + "`n" + $Body + "`n" + $After
    }
    if (-not $Result.EndsWith("`n", [StringComparison]::Ordinal)) {
        $Result += "`n"
    }
    return $Result
}

$CatalogPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$DifficultyPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$LayoutPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
$TacticalPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx'

$Catalog = Read-GammaArenaLtx $CatalogPath
$Difficulties = Read-GammaArenaLtx $DifficultyPath
$Layout = Read-GammaArenaLtx $LayoutPath
$Tactical = Read-GammaArenaLtx $TacticalPath

$Blocks = [ordered]@{}
$Blocks['state-passport'] = @"
| Source | Version |
|---|---|
| Catalog | schema $(Get-RequiredLtxInt $Catalog 'meta' 'schema_version' $CatalogPath) / revision $(Get-RequiredLtxInt $Catalog 'meta' 'revision' $CatalogPath) / generator $(Get-RequiredLtxInt $Catalog 'meta' 'generator_version' $CatalogPath) |
| Difficulties | schema $(Get-RequiredLtxInt $Difficulties 'meta' 'schema_version' $DifficultyPath) / revision $(Get-RequiredLtxInt $Difficulties 'meta' 'revision' $DifficultyPath) |
| Layout | schema $(Get-RequiredLtxInt $Layout 'meta' 'schema_version' $LayoutPath) / revision $(Get-RequiredLtxInt $Layout 'meta' 'revision' $LayoutPath) |
| Tactics | schema $(Get-RequiredLtxInt $Tactical 'meta' 'schema_version' $TacticalPath) / revision $(Get-RequiredLtxInt $Tactical 'meta' 'revision' $TacticalPath) |
"@

if (-not (Test-Path -LiteralPath $DocumentPath)) {
    throw "Arena balance document is missing: $DocumentPath"
}
$Current = [IO.File]::ReadAllText($DocumentPath)
$Expected = Set-GeneratedMarkdownBlocks $Current $Blocks

if ($Verify) {
    if ($Current.Replace("`r`n", "`n").Replace("`r", "`n") -cne $Expected) {
        throw "Arena balance document is stale. Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Update-GammaArenaBalanceDoc.ps1"
    }
    Write-Host 'PASS: Arena balance document is current'
    exit 0
}

[IO.File]::WriteAllText($DocumentPath, $Expected, (New-Object Text.UTF8Encoding($false)))
Write-Host "Updated Arena balance document: $DocumentPath"
