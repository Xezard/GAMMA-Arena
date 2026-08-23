[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$ToolPath = Join-Path $RepoRoot 'tools\Update-GammaArenaBalanceDoc.ps1'
if (-not (Test-Path -LiteralPath $ToolPath)) {
    throw 'Arena balance document generator is missing'
}

function New-BalanceFixture([string]$SourceRoot) {
    $FixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('gamma-arena-balance-' + [guid]::NewGuid().ToString('N'))
    foreach ($RelativePath in @(
        'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx',
        'src\gamedata\scripts\gamma_arena_catalog_discovery.script',
        'src\gamedata\scripts\gamma_arena_catalog.script',
        'src\gamedata\scripts\gamma_arena_generator.script',
        'src\gamedata\scripts\gamma_arena_tactical_director.script'
    )) {
        $Target = Join-Path $FixtureRoot $RelativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $SourceRoot $RelativePath) -Destination $Target
    }
    $Document = Join-Path $FixtureRoot 'docs\arena-balance.md'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Document) | Out-Null
    [IO.File]::WriteAllText($Document, @'
# Gamma Arena balance

<!-- BEGIN GENERATED: state-passport -->
<!-- END GENERATED: state-passport -->
'@, (New-Object Text.UTF8Encoding($false)))
    return $FixtureRoot
}

function Invoke-ExpectedFailure([scriptblock]$Action, [string]$Pattern) {
    $Failed = $false
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $Failed = $true
    }
    if (-not $Failed) { throw "Expected failure matching: $Pattern" }
}

$Fixture = New-BalanceFixture $RepoRoot
try {
    $Document = Join-Path $Fixture 'docs\arena-balance.md'
    & $ToolPath -RepoRoot $Fixture
    $First = [IO.File]::ReadAllText($Document)
    foreach ($Expected in @(
        '| Catalog | schema 4 / revision 5 / generator 5 |',
        '| Difficulties | schema 3 / revision 4 |',
        '| Layout | schema 2 / revision 2 |',
        '| Tactics | schema 1 / revision 1 |'
    )) {
        if (-not $First.Contains($Expected)) {
            throw "Generated state passport is missing: $Expected"
        }
    }

    & $ToolPath -RepoRoot $Fixture
    $Second = [IO.File]::ReadAllText($Document)
    if ($First -cne $Second) { throw 'Arena balance document generation is not idempotent' }

    & $ToolPath -RepoRoot $Fixture -Verify

    $Stale = $Second.Replace('Catalog | schema 4 /', 'Catalog | schema 999 /')
    [IO.File]::WriteAllText($Document, $Stale, (New-Object Text.UTF8Encoding($false)))
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'Update-GammaArenaBalanceDoc\.ps1'
    & $ToolPath -RepoRoot $Fixture

    $Valid = [IO.File]::ReadAllText($Document)
    [IO.File]::WriteAllText(
        $Document,
        $Valid + "<!-- BEGIN GENERATED: state-passport -->`n",
        (New-Object Text.UTF8Encoding($false))
    )
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'markers must exist exactly once'

    [IO.File]::WriteAllText($Document, $Valid, (New-Object Text.UTF8Encoding($false)))
    $Difficulty = Join-Path $Fixture 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
    [IO.File]::AppendAllText($Difficulty, "`n[meta]`nrevision = 4`n")
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'duplicate section'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Malformed balance source partially rewrote the document'
    }
}
finally {
    if (Test-Path -LiteralPath $Fixture) {
        Remove-Item -LiteralPath $Fixture -Recurse -Force
    }
}

Write-Host 'PASS: Arena balance documentation core passed'
