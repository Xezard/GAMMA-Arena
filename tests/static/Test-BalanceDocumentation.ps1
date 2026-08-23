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

& $ToolPath -RepoRoot $RepoRoot -Verify
$RepositoryDocument = [IO.File]::ReadAllText((Join-Path $RepoRoot 'docs\arena-balance.md'))
if (([regex]::Matches($RepositoryDocument, '(?m)^```').Count % 2) -ne 0) {
    throw 'Arena balance document has unbalanced Markdown fences'
}
if (([regex]::Matches($RepositoryDocument, '(?m)^```mermaid$').Count) -ne 1) {
    throw 'Arena balance document must contain exactly one Mermaid diagram'
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

<!-- BEGIN GENERATED: difficulty-dashboard -->
<!-- END GENERATED: difficulty-dashboard -->

<!-- BEGIN GENERATED: actor-equipment -->
<!-- END GENERATED: actor-equipment -->

<!-- BEGIN GENERATED: opponent-budgets -->
<!-- END GENERATED: opponent-budgets -->

<!-- BEGIN GENERATED: arena-tactics -->
<!-- END GENERATED: arena-tactics -->

<!-- BEGIN GENERATED: balance-diagnostics -->
<!-- END GENERATED: balance-diagnostics -->

<!-- BEGIN GENERATED: source-map -->
<!-- END GENERATED: source-map -->
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
        '| Tactics | schema 1 / revision 1 |',
        '| rookie | 2-3 | 25 | 8 | 50% |',
        '| master | 7-10 | 100 | 16 | 80% |',
        '| master | 5% | 15% | 15% | 50% | 15% |',
        '| master | 10% | 25% | 25% | 35% | 5% |',
        '| rookie | 4 / 25 |',
        '| master | 12 / 25 |',
        '| w_pistol | 2 |',
        '| o_heavy | 5 | heavy; powered_exo when exo/proto |',
        '| master | 7 | 15, 15, 14, 14, 14, 14, 14 | 6 | 1 |',
        '| master | 10 | 10 x 10 | 8 | 2 |',
        '| PRIMARY_BAND_PERCENT | 70% |',
        '| max_snipers_per_fight | 1 |',
        '| native_opponent_paths | 6 |',
        '| virtual_capacity | 10 |',
        '| observation_interval_ms | 500 ms |',
        '| report_delay_ms | 1000-3000 ms |',
        '| initial_role_order | pressure -> flank -> support -> anchor |',
        '| minimum_fallback_loadout | 5 budget points |',
        '| derived | master max-team feasibility margin | 40 |',
        '| blind_spot | installed merge item cardinality, DPS, penetration, TTK, win rate | runtime measurement |',
        '| player class weights and enemy envelopes | `gamma_arena_difficulties.ltx` |'
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
    $DifficultyOriginal = [IO.File]::ReadAllText($Difficulty)
    [IO.File]::AppendAllText($Difficulty, "`n[meta]`nrevision = 4`n")
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'duplicate section'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Malformed balance source partially rewrote the document'
    }

    [IO.File]::WriteAllText($Difficulty, $DifficultyOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture
    $DifficultyChanged = $DifficultyOriginal.Replace('enemy_total_budget = 100', 'enemy_total_budget = 101')
    [IO.File]::WriteAllText($Difficulty, $DifficultyChanged, (New-Object Text.UTF8Encoding($false)))
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'document is stale'

    [IO.File]::WriteAllText($Difficulty, $DifficultyOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture

    $Layout = Join-Path $Fixture 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
    $LayoutOriginal = [IO.File]::ReadAllText($Layout)
    [IO.File]::WriteAllText(
        $Layout,
        $LayoutOriginal.Replace('virtual_capacity = 10', 'virtual_capacity = 9'),
        (New-Object Text.UTF8Encoding($false))
    )
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'document is stale'

    [IO.File]::WriteAllText($Layout, $LayoutOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture
    $Tactical = Join-Path $Fixture 'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx'
    $TacticalOriginal = [IO.File]::ReadAllText($Tactical)
    [IO.File]::WriteAllText(
        $Tactical,
        $TacticalOriginal.Replace('observation_interval_ms = 500', 'observation_interval_ms = 501'),
        (New-Object Text.UTF8Encoding($false))
    )
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'document is stale'

    [IO.File]::WriteAllText($Tactical, $TacticalOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture
    $Generator = Join-Path $Fixture 'src\gamedata\scripts\gamma_arena_generator.script'
    $GeneratorText = [IO.File]::ReadAllText($Generator)
    $Renamed = $GeneratorText.Replace('local PRIMARY_BAND_PERCENT = 70', 'local PRIMARY_BAND_RENAMED = 70')
    [IO.File]::WriteAllText($Generator, $Renamed, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'PRIMARY_BAND_PERCENT'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Missing Lua balance symbol partially rewrote the document'
    }
}
finally {
    if (Test-Path -LiteralPath $Fixture) {
        Remove-Item -LiteralPath $Fixture -Recurse -Force
    }
}

Write-Host 'PASS: Arena balance documentation core passed'
