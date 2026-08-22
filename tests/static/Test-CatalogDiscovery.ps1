[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ProductionPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog_discovery.script'
$TestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_catalog_discovery.script'

if (-not (Test-Path -LiteralPath $ProductionPath)) {
    throw 'Dynamic catalog discovery production module is missing'
}
if (-not (Test-Path -LiteralPath $TestPath)) {
    throw 'Dynamic catalog discovery dev suite is missing'
}

$Production = Get-Content -Raw -LiteralPath $ProductionPath
$Tests = Get-Content -Raw -LiteralPath $TestPath

foreach ($Marker in @(
    'function discover',
    'candidate_section',
    'enumerate_sections',
    'read_string',
    'read_u32',
    'fingerprint_parts',
    'w_pistol',
    'w_smg',
    'w_shotgun',
    'w_rifle',
    'w_sniper',
    'o_light',
    'o_medium',
    'o_sci',
    'o_heavy',
    'wpn_knife'
)) {
    if (-not $Production.Contains($Marker)) {
        throw "Dynamic catalog discovery contract is missing marker: $Marker"
    }
}

if ($Production -notmatch 'pcall') {
    throw 'Dynamic catalog discovery must guard injected engine boundaries'
}
if ($Production -notmatch 'table\.sort') {
    throw 'Dynamic catalog discovery must normalize engine enumeration order'
}
if ($Production -match 'xrs_rnd_npc_loadout|wpn_addon_rifle|addon_medium_outfit') {
    throw 'Production discovery must use semantic metadata without fixture IDs or native loadout mutation'
}

foreach ($CaseName in @(
    'catalog_discovery_accepts_semantic_installed_gear',
    'catalog_discovery_prefilters_irrelevant_system_sections',
    'catalog_discovery_is_order_stable',
    'catalog_discovery_enumeration_failure_falls_back'
)) {
    if (-not $Tests.Contains($CaseName)) {
        throw "Dynamic catalog discovery test is missing: $CaseName"
    }
}

Write-Host 'PASS: dynamic catalog discovery static contract passed'

$CatalogPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script'
$GeneratorTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_generator.script'
$Catalog = Get-Content -Raw -LiteralPath $CatalogPath
$GeneratorTests = Get-Content -Raw -LiteralPath $GeneratorTestPath
foreach ($Marker in @(
    'gamma_arena_catalog_discovery.discover',
    'enumerate_system_sections',
    'read_system_string',
    'read_system_u32',
    'read_loadout_string',
    'enumerate_loadout_keys',
    'r_string_ex',
    'r_line_ex',
    'selection_mode',
    'minimum_loadout_cost'
)) {
    if (-not $Catalog.Contains($Marker)) {
        throw "Dynamic catalog integration is missing marker: $Marker"
    }
}
if (-not $GeneratorTests.Contains('catalog_augments_effective_system_without_cartesian_product')) {
    throw 'Dynamic catalog integration regression case is missing'
}
if (-not $GeneratorTests.Contains('extended GAMMA loadout readers are used')) {
    throw 'Dynamic catalog integration must cover extended GAMMA loadout inheritance readers'
}
Write-Host 'PASS: dynamic catalog integration static contract passed'

$GeneratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_generator.script'
$ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_validator.script'
$Generator = Get-Content -Raw -LiteralPath $GeneratorPath
$Validator = Get-Content -Raw -LiteralPath $ValidatorPath
foreach ($Contract in @(
    @{ Content = $Generator; Marker = 'selection_mode' },
    @{ Content = $Generator; Marker = 'minimum_loadout_cost' },
    @{ Content = $Validator; Marker = 'selection_mode' },
    @{ Content = $Validator; Marker = 'minimum_loadout_cost' }
)) {
    if (-not $Contract.Content.Contains($Contract.Marker)) {
        throw "Staged loadout production contract is missing marker: $($Contract.Marker)"
    }
}
Write-Host 'PASS: staged loadout static contract passed'

$NpcAliasPath = Join-Path $RepoRoot 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx'
$SkipPath = Join-Path $RepoRoot 'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx'
$NpcAliases = Get-Content -Raw -LiteralPath $NpcAliasPath
$SkipEntries = Get-Content -Raw -LiteralPath $SkipPath
$Factions = @('stalker', 'bandit', 'csky', 'army', 'dolg', 'freedom', 'ecolog', 'killer', 'monolith')
$ProfileBases = @{ stalker='stalker'; bandit='bandit'; csky='csky'; army='military'; dolg='duty'; freedom='freedom'; ecolog='ecolog'; killer='killer'; monolith='monolith' }
$Ranks = @('novice', 'trainee', 'experienced', 'veteran')
foreach ($Faction in $Factions) {
    for ($RankIndex = 0; $RankIndex -lt $Ranks.Count; $RankIndex++) {
        $Alias = "gamma_arena_${Faction}_$($Ranks[$RankIndex])"
        if (-not $NpcAliases.Contains("[$Alias]:sim_default_$($ProfileBases[$Faction])_$RankIndex")) {
            throw "Arena human profile alias is missing: $Alias"
        }
        if ($SkipEntries -notmatch "(?m)^$([regex]::Escape($Alias))\s*=\s*$([regex]::Escape($Faction))\s*$" ) {
            throw "Arena human profile is missing from GAMMA loadout skip table: $Alias"
        }
    }
}
foreach ($Marker in @('PROFILE_FACTIONS', 'profiles_by_faction')) {
    if (-not $Catalog.Contains($Marker)) { throw "Faction catalog contract is missing marker: $Marker" }
}
if (-not $Generator.Contains('enemy_faction')) { throw 'Generator must choose one deterministic enemy faction per fight' }
if (-not $Catalog.Contains('open_loadouts') -or -not $Catalog.Contains('weapons_by_profile')) { throw 'Catalog must index effective GAMMA faction/rank weapon pools' }
if (-not $Generator.Contains('weapons_by_profile')) { throw 'Generator must prefer the selected profile weapon pool' }
if (-not $Validator.Contains('expected_community')) { throw 'Runtime validator must validate the selected profile community' }
Write-Host 'PASS: faction cohort static contract passed'
