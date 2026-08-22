[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
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
    'armor_class',
    'repair_type',
    'powered_exo',
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
if (-not $Production.Contains('slot = slot')) {
    throw 'Dynamic catalog discovery must retain the effective weapon inventory slot'
}
if ($Production -match 'xrs_rnd_npc_loadout|wpn_addon_rifle|addon_medium_outfit') {
    throw 'Production discovery must use semantic metadata without fixture IDs or native loadout mutation'
}

foreach ($CaseName in @(
    'catalog_discovery_accepts_semantic_installed_gear',
    'catalog_discovery_powered_exo_is_separate_from_heavy',
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
    'minimum_loadout_cost',
    'primary_weapon_list',
    'secondary_weapon_list',
    'weapon_pools_by_profile',
    'primary_share_percent'
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
if ($Catalog -notmatch 'difficulty_manifest_v3' -or $Catalog -notmatch 'PLAYER_WEAPON_WEIGHT_KEYS' -or $Catalog -notmatch 'PLAYER_ARMOR_WEIGHT_KEYS') {
    throw 'Weighted player class tables are missing from the catalog contract'
}
if ($Catalog -notmatch 'schema_version\s*=\s*4' -or $Catalog -notmatch 'generator_version\s*=\s*5') {
    throw 'Catalog snapshot version markers are stale'
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
if (-not $Catalog.Contains('open_loadouts') -or -not $Catalog.Contains('weapon_pools_by_profile')) { throw 'Catalog must index separate effective GAMMA faction/rank weapon pools' }
if (-not $Validator.Contains('expected_community')) { throw 'Runtime validator must validate the selected profile community' }
Write-Host 'PASS: faction cohort static contract passed'

$DifficultyPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$Difficulty = Get-Content -Raw -LiteralPath $DifficultyPath
foreach ($Expected in @(
    '(?ms)\[ga_difficulty_rookie\].*?enemy_min\s*=\s*2\s*.*?enemy_max\s*=\s*3\s*.*?enemy_total_budget\s*=\s*25\s*.*?player_loadout_budget\s*=\s*8\s*.*?weapon_weight_pistol\s*=\s*50\s*.*?weapon_weight_smg\s*=\s*30\s*.*?weapon_weight_shotgun\s*=\s*15\s*.*?weapon_weight_rifle\s*=\s*5\s*.*?weapon_weight_sniper\s*=\s*0\s*.*?armor_weight_light\s*=\s*55\s*.*?armor_weight_medium\s*=\s*30\s*.*?armor_weight_scientific\s*=\s*10\s*.*?armor_weight_heavy\s*=\s*5\s*.*?armor_weight_powered_exo\s*=\s*0',
    '(?ms)\[ga_difficulty_stalker\].*?enemy_min\s*=\s*3\s*.*?enemy_max\s*=\s*5\s*.*?enemy_total_budget\s*=\s*50\s*.*?player_loadout_budget\s*=\s*11\s*.*?weapon_weight_pistol\s*=\s*25\s*.*?weapon_weight_smg\s*=\s*35\s*.*?weapon_weight_shotgun\s*=\s*20\s*.*?weapon_weight_rifle\s*=\s*18\s*.*?weapon_weight_sniper\s*=\s*2\s*.*?armor_weight_light\s*=\s*30\s*.*?armor_weight_medium\s*=\s*40\s*.*?armor_weight_scientific\s*=\s*20\s*.*?armor_weight_heavy\s*=\s*9\s*.*?armor_weight_powered_exo\s*=\s*1',
    '(?ms)\[ga_difficulty_veteran\].*?enemy_min\s*=\s*5\s*.*?enemy_max\s*=\s*7\s*.*?enemy_total_budget\s*=\s*75\s*.*?player_loadout_budget\s*=\s*14\s*.*?weapon_weight_pistol\s*=\s*10\s*.*?weapon_weight_smg\s*=\s*25\s*.*?weapon_weight_shotgun\s*=\s*20\s*.*?weapon_weight_rifle\s*=\s*38\s*.*?weapon_weight_sniper\s*=\s*7\s*.*?armor_weight_light\s*=\s*15\s*.*?armor_weight_medium\s*=\s*30\s*.*?armor_weight_scientific\s*=\s*25\s*.*?armor_weight_heavy\s*=\s*25\s*.*?armor_weight_powered_exo\s*=\s*5',
    '(?ms)\[ga_difficulty_master\].*?enemy_min\s*=\s*7\s*.*?enemy_max\s*=\s*10\s*.*?enemy_total_budget\s*=\s*100\s*.*?player_loadout_budget\s*=\s*16\s*.*?weapon_weight_pistol\s*=\s*5\s*.*?weapon_weight_smg\s*=\s*15\s*.*?weapon_weight_shotgun\s*=\s*15\s*.*?weapon_weight_rifle\s*=\s*50\s*.*?weapon_weight_sniper\s*=\s*15\s*.*?armor_weight_light\s*=\s*5\s*.*?armor_weight_medium\s*=\s*20\s*.*?armor_weight_scientific\s*=\s*20\s*.*?armor_weight_heavy\s*=\s*35\s*.*?armor_weight_powered_exo\s*=\s*20'
)) {
    if ($Difficulty -notmatch $Expected) { throw 'Difficulty budget/count/primary-share matrix is stale' }
}
Write-Host 'PASS: expanded difficulty balance contract passed'

if ($Production -notmatch 'read_string\(source, section, "repair_type"\)\s*==\s*"outfit_exo"[\s\S]{0,180}armor_class\s*=\s*"powered_exo"') {
    throw 'Dynamic catalog discovery must classify repair_type outfit_exo as powered_exo, never generic heavy'
}
$PlayerLoadoutStart = $Generator.IndexOf('function player_loadout')
$PlayerLoadoutEnd = $Generator.IndexOf('local function random_knife', $PlayerLoadoutStart)
if ($PlayerLoadoutStart -lt 0 -or $PlayerLoadoutEnd -le $PlayerLoadoutStart) {
    throw 'Weighted player loadout selection must remain structurally testable'
}
$PlayerLoadout = $Generator.Substring($PlayerLoadoutStart, $PlayerLoadoutEnd - $PlayerLoadoutStart)
if ($PlayerLoadout -match 'pick_affordable_band') {
    throw 'Player loadouts must use weighted class selection, not maximum-cost affordable-band selection'
}
if ($PlayerLoadout -notmatch 'select_player_class_pair[\s\S]{0,400}actor_class_pair' -or $Generator -notmatch 'weapon_weight\s*\*\s*armor_weight') {
    throw 'Player loadouts must retain weighted weapon/armor class-pair selection'
}
Write-Host 'PASS: natural-death and weighted-loadout regression policy passed'
