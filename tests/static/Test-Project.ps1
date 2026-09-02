[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        $script:Failures.Add($Message)
    }
}

function Get-RelativeRepoPath([string]$Path) {
    return $Path.Substring($RepoRoot.Length).TrimStart('\', '/').Replace('/', '\')
}

function Test-TextPattern([string]$Path, [string]$Pattern) {
    return [bool](Select-String -LiteralPath $Path -Pattern $Pattern -Quiet)
}

function Assert-NoReservedLuaFormalParameters([string]$Path) {
    $reserved = @(
        'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
        'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
        'return', 'then', 'true', 'until', 'while'
    )
    $declarationPattern = '(?ms)\bfunction(?:\s+[A-Za-z_][A-Za-z0-9_:.]*)?\s*\((?<parameters>[^)]*)\)'
    $Content = Get-Content -LiteralPath $Path -Raw

    foreach ($Declaration in [regex]::Matches($Content, $declarationPattern)) {
        foreach ($Parameter in $Declaration.Groups['parameters'].Value.Split(',')) {
            $Name = $Parameter.Trim()
            if ($Name -ne '...' -and $reserved -contains $Name) {
                Assert-True $false "Reserved Lua formal parameter ${Name}: $(Get-RelativeRepoPath $Path)"
            }
        }
    }
}

$LuaFormalFixtureRoot = Join-Path $RepoRoot ('.reserved-lua-formal-fixtures-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $LuaFormalFixtureRoot -Force | Out-Null
    $NamedFixture = Join-Path $LuaFormalFixtureRoot 'named.script'
    $AnonymousFixture = Join-Path $LuaFormalFixtureRoot 'anonymous.script'
    $ReservedFixture = Join-Path $LuaFormalFixtureRoot 'reserved.script'
    [IO.File]::WriteAllText($NamedFixture, "function named(first, second, ...)`nend`n")
    [IO.File]::WriteAllText($AnonymousFixture, "local callback = function(alpha, beta, ...)`nend`n")
    [IO.File]::WriteAllText($ReservedFixture, "local function invalid(now, then)`nend`n")

    $OriginalFailures = $script:Failures
    $FixtureFailures = New-Object System.Collections.Generic.List[string]
    $script:Failures = $FixtureFailures
    Assert-NoReservedLuaFormalParameters $NamedFixture
    Assert-NoReservedLuaFormalParameters $AnonymousFixture
    Assert-NoReservedLuaFormalParameters $ReservedFixture
    $script:Failures = $OriginalFailures

    Assert-True ($FixtureFailures.Count -eq 1) 'Lua reserved-formal self-check must accept named and anonymous ordinary identifiers and reject exactly one reserved formal.'
    if ($FixtureFailures.Count -eq 1) {
        $ReservedDiagnostic = $FixtureFailures[0]
        Assert-True ($ReservedDiagnostic -match [regex]::Escape((Get-RelativeRepoPath $ReservedFixture))) 'Lua reserved-formal self-check diagnostic must include the fixture path.'
        Assert-True ($ReservedDiagnostic -match '\bthen\b') 'Lua reserved-formal self-check diagnostic must include the reserved keyword.'
    }
}
finally {
    $script:Failures = $OriginalFailures
    if (Test-Path -LiteralPath $LuaFormalFixtureRoot) {
        Remove-Item -LiteralPath $LuaFormalFixtureRoot -Recurse -Force
    }
}

Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'VERSION')) 'VERSION is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'src\gamedata')) 'src/gamedata is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot '.gitattributes')) '.gitattributes is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot '.gitignore')) '.gitignore is missing'
$Task4V9ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_validator_v9.script'
$Task4V8ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_validator_v8.script'
$Task4V9SchemaPath = Join-Path $RepoRoot 'schemas\fight-spec-v9.md'
$Task4V9GoldenPath = Join-Path $RepoRoot 'tests\fixtures\golden-fights-v9.txt'
Assert-True (Test-Path -LiteralPath $Task4V9ValidatorPath) 'Task 4 RED: sole v9 validator is missing.'
Assert-True (-not (Test-Path -LiteralPath $Task4V8ValidatorPath)) 'Task 4 RED: legacy v8 validator is still active.'
Assert-True (Test-Path -LiteralPath $Task4V9SchemaPath) 'Task 4 RED: sole v9 schema is missing.'
Assert-True (Test-Path -LiteralPath $Task4V9GoldenPath) 'Task 4 RED: v9 golden fixture is missing.'
$Task4FightSpecPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_spec.script'
$Task4FightSpec = Get-Content -LiteralPath $Task4FightSpecPath -Raw
foreach ($Marker in @('schema_version = 9','"ga9-"','device = 4','catalog_schema_version','catalog_revision','layout_hash')) {
    Assert-True ($Task4FightSpec -match [regex]::Escape($Marker)) "Task 4 RED: v9 canonicalizer marker is missing: $Marker"
}
foreach ($LegacyMarker in @('"ga8-"','loadout.kind == "legacy"','legacy_items')) {
    Assert-True ($Task4FightSpec -notmatch [regex]::Escape($LegacyMarker)) "Task 4 RED: legacy canonicalizer acceptance remains: $LegacyMarker"
}
if (Test-Path -LiteralPath $Task4V9ValidatorPath) {
    $Task4V9Validator = Get-Content -LiteralPath $Task4V9ValidatorPath -Raw
    foreach ($Marker in @('spec.schema_version ~= 9','device = true','entry.quantity ~= 1','entry.equipped_slot ~= "device"','GA_FIGHTSPEC_OPPONENT_DEVICE_INVALID')) {
        Assert-True ($Task4V9Validator -match [regex]::Escape($Marker)) "Task 4 strict v9 validator marker is missing: $Marker"
    }
    Assert-True ($Task4V9Validator -notmatch 'gamma_arena_(random|device)_generator') 'Task 4 validator must never rerun Random device selection.'
}
$Task4StaticSource = Get-Content -LiteralPath $PSCommandPath -Raw
foreach ($ProtectionLabel in @(
    'Task 4 current generator composition protection',
    'Task 4 current generator RNG isolation protection',
    'Task 4 current ammo scaling protection',
    'Task 4 current grenade generation protection',
    'Task 4 current medical generation protection',
    'Task 4 current actor quarantine protection',
    'Task 4 current affordability and diversity protection',
    'Task 4 current resolved layout and routing protection',
    'Task 4 current exact runtime ammo protection'
)) {
    Assert-True (([regex]::Matches($Task4StaticSource, [regex]::Escape($ProtectionLabel))).Count -ge 2) "Task 4 review RED: missing version-neutral regression gate: $ProtectionLabel"
}
$Task7RepositoryCheckout = Test-Path -LiteralPath (Join-Path $RepoRoot '.git')
$Task7VersionPath = Join-Path $RepoRoot 'VERSION'
$AddonVersion = if (Test-Path -LiteralPath $Task7VersionPath -PathType Leaf) { (Get-Content -LiteralPath $Task7VersionPath -Raw).Trim() } else { '' }
if ($Task7RepositoryCheckout) { Assert-True ($AddonVersion -ceq '0.5.1') 'Task 7 release version must be exactly 0.5.1.' }
Assert-True ($AddonVersion -match '^\d+\.\d+\.\d+$') 'VERSION must be a plain SemVer triplet.'
if ($Task7RepositoryCheckout) {
$Task7BuildPath = Join-Path $RepoRoot 'tools\Build-GammaArena.ps1'
Assert-True (Test-Path -LiteralPath $Task7BuildPath -PathType Leaf) 'Task 7 release build script is missing.'
if (Test-Path -LiteralPath $Task7BuildPath -PathType Leaf) {
$Task7BuildContent = Get-Content -LiteralPath $Task7BuildPath -Raw
Assert-True ($Task7BuildContent.Contains('schemas\fight-spec-v9.md')) 'Task 7 build must package the sole v9 schema.'
Assert-True ($Task7BuildContent.Contains('tests\fixtures\custom-catalog-v10.json')) 'Task 7 Dev build must package the v10 catalog fixture.'
Assert-True ($Task7BuildContent.Contains('fight_spec_schema_version = 9')) 'Task 7 manifest must publish FightSpec 9.'
Assert-True ($Task7BuildContent.Contains('catalog_schema_version = 10')) 'Task 7 manifest must publish catalog schema 10.'
Assert-True ($Task7BuildContent.Contains('catalog_revision = 11')) 'Task 7 manifest must publish catalog revision 11.'
Assert-True ($Task7BuildContent.Contains('generator_version = 11')) 'Task 7 manifest must publish generator 11.'
Assert-True ($Task7BuildContent -notmatch '(?:fight-spec|golden-fights|golden-random-selections)-v[1-8]|custom-catalog-v1\.json') 'Task 7 build tooling must reference only current FightSpec/catalog artifacts.'
}
$Task7CurrentValidators = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts') -File -Filter 'gamma_arena_fight_validator_v*.script')
$Task7CurrentGoldenFixtures = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tests\fixtures') -File -Filter 'golden-fights-v*.txt')
Assert-True ($Task7CurrentValidators.Count -eq 1 -and $Task7CurrentValidators[0].Name -ceq 'gamma_arena_fight_validator_v9.script') 'Task 7 must publish exactly one active FightSpec validator: v9.'
Assert-True ($Task7CurrentGoldenFixtures.Count -eq 1 -and $Task7CurrentGoldenFixtures[0].Name -ceq 'golden-fights-v9.txt') 'Task 7 must publish exactly one FightSpec golden fixture: v9.'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'tests\fixtures\custom-catalog-v10.json')) 'Task 7 current catalog fixture custom-catalog-v10.json is missing.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'tests\fixtures\custom-catalog-v1.json'))) 'Task 7 stale custom-catalog-v1.json must be removed.'
}

$AllLuaScripts = @(Get-ChildItem -LiteralPath $RepoRoot -File -Recurse -Filter '*.script' | Where-Object {
    $_.FullName -notmatch '[\\/](dist|build)[\\/]'
})
foreach ($Script in $AllLuaScripts) {
    Assert-True (-not (Test-TextPattern $Script.FullName '(?m)\b[A-Za-z_][A-Za-z0-9_]*\.[0-9][A-Za-z0-9_.]*\s*=')) "Invalid bare Lua table key containing a dot: $(Get-RelativeRepoPath $Script.FullName)"
}

foreach ($ScriptRoot in @('src\gamedata\scripts', 'dev\gamedata\scripts')) {
    $ScriptDirectory = Join-Path $RepoRoot $ScriptRoot
    if (Test-Path -LiteralPath $ScriptDirectory) {
        foreach ($Script in @(Get-ChildItem -LiteralPath $ScriptDirectory -File -Recurse -Filter '*.script')) {
            Assert-NoReservedLuaFormalParameters $Script.FullName
        }
    }
}

$ForbiddenOverrides = @(
    'gamedata\scripts\ui_main_menu.script',
    'gamedata\scripts\ui_mm_faction_select.script',
    'gamedata\scripts\axr_main.script',
    'gamedata\scripts\bind_stalker_ext.script',
    'gamedata\configs\system.ltx',
    'gamedata\configs\items\settings\npc_loadouts\npc_loadouts.ltx'
)

$SourceGamedata = Join-Path $RepoRoot 'src\gamedata'
$AllSourceFiles = @()
if (Test-Path -LiteralPath $SourceGamedata) {
    $AllSourceFiles = @(Get-ChildItem -LiteralPath $SourceGamedata -File -Recurse)

    foreach ($File in $AllSourceFiles) {
        $Relative = ('gamedata\' + $File.FullName.Substring($SourceGamedata.Length).TrimStart('\', '/')).Replace('/', '\')
        Assert-True (-not ($ForbiddenOverrides -contains $Relative)) "Forbidden base-game override: $Relative"

        $Content = Get-Content -LiteralPath $File.FullName -Raw
        Assert-True ($Content -notmatch '(?im)\b(TODO|FIXME)\b|<placeholder>|D:\\Anomaly') "Forbidden placeholder or D:\Anomaly path: $(Get-RelativeRepoPath $File.FullName)"

        if ($File.Extension -ieq '.xml') {
            try {
                [xml]$ParsedXml = $Content
            }
            catch {
                Assert-True $false "Malformed XML: $(Get-RelativeRepoPath $File.FullName)"
            }
        }
    }

    $ArenaScripts = @($AllSourceFiles | Where-Object {
        $RelativePath = $_.FullName.Substring($SourceGamedata.Length).TrimStart('\', '/').Replace('/', '\')
        $RelativePath -match '^scripts\\' -and ($_.Name -like 'gamma_arena_*' -or $_.Name -like 'ga_*')
    })
    foreach ($Script in $ArenaScripts) {
        Assert-True (-not (Test-TextPattern $Script.FullName '\bmath\.random(seed)?\b')) "Non-deterministic random call: $(Get-RelativeRepoPath $Script.FullName)"
        Assert-True (-not (Test-TextPattern $Script.FullName '(?is)\bw_value\s*\([^\)]*,\s*nil\s*\)')) "w_value(..., nil) writes an empty string; use remove_line: $(Get-RelativeRepoPath $Script.FullName)"
    }

    $MutationNamePattern = '(?i)(spawn|give|remove|teleport|set|add|delete|replace|patch|inject|override|mutat)'
    foreach ($File in $AllSourceFiles) {
        if ($File.BaseName -match $MutationNamePattern) {
            Assert-True ($File.BaseName -match '^(gamma_arena|ga_)') "Mutation-oriented file must use gamma_arena or ga_ prefix: $(Get-RelativeRepoPath $File.FullName)"
        }
    }

    $CatalogFiles = @($AllSourceFiles | Where-Object {
        $RelativePath = $_.FullName.Substring($SourceGamedata.Length).TrimStart('\', '/').Replace('/', '\')
        ($RelativePath -match '^configs\\gamma_arena\\' -and $_.Extension -ieq '.ltx') -or
            $_.Name -match '(?i)(npc.*catalog|catalog.*npc|npc_catalog)'
    })
    $MutantPattern = '(?i)(?:^|[^a-z0-9])(bloodsucker|boar|burer|cat|chimera|controller|dog|flesh|fracture|gigant|izlom|karlik|pseudodog|pseudogiant|psy[_-]?dog|snork|tushkano|zombie|mutant)(?:$|[^a-z0-9])'
    foreach ($Catalog in $CatalogFiles) {
        Assert-True (-not (Test-TextPattern $Catalog.FullName $MutantPattern)) "NPC catalog contains known mutant entry: $(Get-RelativeRepoPath $Catalog.FullName)"
    }

    $MenuXmlFiles = @($AllSourceFiles | Where-Object { $_.Name -match '(?i)(main.*menu|menu.*main)' -and $_.Extension -ieq '.xml' })
    foreach ($MenuXml in $MenuXmlFiles) {
        [xml]$MenuDocument = Get-Content -LiteralPath $MenuXml.FullName -Raw
        $DxmlInserts = @($MenuDocument.SelectNodes('//*[local-name()="insert"]'))
        foreach ($DxmlInsert in $DxmlInserts) {
            $InsertBlock = $DxmlInsert.OuterXml
            if ($InsertBlock -match 'btn_gamma_arena') {
                Assert-True ($InsertBlock -match '(?is)\bnot\s+[\w.:_]+\s*:\s*(find|exists|query|has)\s*\(\s*["'']btn_gamma_arena["'']\s*\)') "DXML Gamma Arena insert lacks a negative duplicate query guard: $(Get-RelativeRepoPath $MenuXml.FullName)"
            }
        }
    }
}

$ReleaseFiles = $AllSourceFiles
foreach ($File in $ReleaseFiles) {
    Assert-True ($File.Name -notmatch '(?i)^gamma_arena_test_') "Release source contains test fixture: $(Get-RelativeRepoPath $File.FullName)"
}

$Task2ScriptContracts = @(
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_assert.script'; Namespace = 'gamma_arena_test_assert'; Required = @('(?m)^function\s+equals\s*\(', '(?m)^function\s+is_true\s*\(', '(?m)^function\s+is_false\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_runner.script'; Namespace = 'gamma_arena_test_runner'; Required = @('(?m)^function\s+run_case\s*\(', '(?m)^function\s+run_all\s*\(', '(?m)^function\s+on_game_start\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_domain.script'; Namespace = 'gamma_arena_test_domain'; Required = @('(?m)^function\s+run\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_result.script'; Namespace = 'gamma_arena_result'; Required = @('(?m)^function\s+ok\s*\(', '(?m)^function\s+err\s*\(', '(?m)^function\s+is_ok\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_log.script'; Namespace = 'gamma_arena_log'; Required = @('(?m)^function\s+info\s*\(', '(?m)^function\s+warn\s*\(', '(?m)^function\s+error\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_rng.script'; Namespace = 'gamma_arena_rng'; Required = @('(?m)^function\s+normalize_uint32\s*\(', '(?m)^function\s+derive_seed\s*\(', '(?m)^function\s+new\s*\(', '(?m)^function\s+random_session_seed\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_state_machine.script'; Namespace = 'gamma_arena_state_machine'; Required = @('(?m)^states\s*=\s*\{', '(?m)^events\s*=\s*\{', '(?m)^function\s+transition\s*\(') }
)

$Task3ScriptContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_number.script'; Namespace = 'gamma_arena_number'; Required = @('(?m)^function\s+is_finite\s*\(', '(?m)^function\s+is_integer\s*\(', '(?m)^function\s+is_positive_integer\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_catalog.script'; Namespace = 'gamma_arena_catalog'; Required = @('(?m)^function\s+load\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_catalog_discovery.script'; Namespace = 'gamma_arena_catalog_discovery'; Required = @('(?m)^function\s+discover\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_weapon_diagnostics.script'; Namespace = 'gamma_arena_weapon_diagnostics'; Required = @('(?m)^function\s+snapshot\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_mode_skirmish.script'; Namespace = 'gamma_arena_mode_skirmish'; Required = @('(?m)^function\s+id\s*\(', '(?m)^function\s+difficulty_envelope\s*\(', '(?m)^function\s+next_fight_index\s*\(', '(?m)^function\s+validate_session\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_generator.script'; Namespace = 'gamma_arena_generator'; Required = @('(?m)^function\s+generate\s*\(', '(?m)^function\s+stable_encode\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_device_generator.script'; Namespace = 'gamma_arena_device_generator'; Required = @('(?m)^function\s+select\s*\(', '(?m)^function\s+generate\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_grenade_generator.script'; Namespace = 'gamma_arena_grenade_generator'; Required = @('(?m)^function\s+generate_actor\s*\(', '(?m)^function\s+generate_enemy\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_medical_generator.script'; Namespace = 'gamma_arena_medical_generator'; Required = @('(?m)^function\s+generate_actor\s*\(', '(?m)^function\s+allocate_enemies\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_mags_redux.script'; Namespace = 'gamma_arena_mags_redux'; Required = @('(?m)^function\s+new\s*\(', 'bonus_descriptors', 'initialize', 'GA_MAGS_REDUX_API_INVALID', 'GA_MAGS_REDUX_VERIFY_FAILED') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_npc_medical.script'; Namespace = 'gamma_arena_npc_medical'; Required = @('(?m)^function\s+new\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_validator.script'; Namespace = 'gamma_arena_validator'; Required = @('(?m)^function\s+validate\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_layout_adapter.script'; Namespace = 'gamma_arena_layout_adapter'; Required = @('(?m)^function\s+new\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'; Namespace = 'gamma_arena_test_generator'; Required = @('(?m)^function\s+run\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_catalog_discovery.script'; Namespace = 'gamma_arena_test_catalog_discovery'; Required = @('(?m)^function\s+run\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_layout_adapter.script'; Namespace = 'gamma_arena_test_layout_adapter'; Required = @('(?m)^function\s+run\s*\(') }
    , [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_mags_redux.script'; Namespace = 'gamma_arena_test_mags_redux'; Required = @('(?m)^function\s+run\s*\(', 'mags_redux_absent_api_is_a_noop', 'mags_redux_partial_api_fails_closed', 'mags_redux_supported_weapons_receive_two_each', 'mags_redux_pouch_exhaustion_is_not_a_loadout_failure') }
    , [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_fight_spec.script'; Namespace = 'gamma_arena_fight_spec'; Required = @('(?m)^function\s+canonicalize\s*\(', '(?m)^function\s+stable_encode\s*\(', '(?m)^function\s+content_hash\s*\(', '(?m)^function\s+layout_hash\s*\(', '(?m)^function\s+copy\s*\(', 'GA_FIGHT_SPEC_ARRAY', 'GA_FIGHT_SPEC_ITEM_LIMIT', 'MAX_SAFE_INTEGER', 'max_physical_items_per_participant', 'loadout\.kind\s*==\s*"items"', 'catalog\.fingerprint', 'catalog_schema_version', 'catalog_revision', 'layout_hash', 'schema_version\s*=\s*9', 'fight_id\s*=\s*"ga9-"', 'device\s*=\s*4') }
    , [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_fight_validator_v9.script'; Namespace = 'gamma_arena_fight_validator_v9'; Required = @('(?m)^function\s+validate\s*\(\s*spec\s*,\s*catalog\s*,\s*layout\s*,\s*runtime\s*\)', 'GA_FIGHTSPEC_UNKNOWN_FIELD', 'GA_FIGHTSPEC_FORBIDDEN_FIELD', 'GA_FIGHTSPEC_ITEM_LIMIT', 'max_physical_items_per_participant', 'exact_keys', 'catalog\.items', 'catalog\.ranks', 'catalog\.factions', 'profile\.alias', 'runtime_community', 'arena_enemy', 'opponent_spawn_slots', 'ammo_sections', 'helmet_allowed', 'healing', 'gamma_arena_fight_spec\.canonicalize', 'gamma_arena_fight_spec\.stable_encode', 'session_seed\s*=\s*function', 'fight_index\s*=\s*function', 'fight_id\s*=\s*function', 'actor\s*=\s*function', 'opponents\s*=\s*function', 'tactical_routes\s*=\s*function', 'stable_encode\s*=\s*function', '(?m)^local function\s+valid_vertex\s*\(', 'value\s*<\s*4294967295', 'used_opponent_slots', 'GA_FIGHTSPEC_OPPONENT_SLOT_DUPLICATE', 'GA_FIGHTSPEC_DEVICE_INVALID', 'GA_FIGHTSPEC_OPPONENT_DEVICE_INVALID', 'spec\.schema_version\s*~=\s*9', '"ga9-"') }
    , [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_fight_spec.script'; Namespace = 'gamma_arena_test_fight_spec'; Required = @('(?m)^function\s+run\s*\(', 'canonicalizes_v9_exact_identity_and_device_order', 'rejects_legacy_loadouts_and_invalid_devices', 'validator_enforces_v9_identity_versions_and_devices', 'validator_never_reruns_random_device_selection', 'fight_spec_enforces_per_participant_physical_item_cap', 'fight_spec_binds_identity_layout_and_dense_arrays', 'fight_spec_rejects_invalid_resolved_layout_identity_fields', 'validator_enforces_per_participant_physical_item_cap', 'validator_enforces_engine_vertex_uint32_boundaries', 'validator_enforces_physical_participant_contracts') }
)

$Task4CurrentGeneratorContracts = @(
    [PSCustomObject]@{
        Protection = 'Task 4 current generator composition protection'
        Path = 'src\gamedata\scripts\gamma_arena_generator.script'
        Required = @('gamma_arena_fight_builder\.generate', 'gamma_arena_fight_spec\.stable_encode')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current generator composition protection'
        Path = 'src\gamedata\scripts\gamma_arena_fight_builder.script'
        Required = @('gamma_arena_random_generator\.build_draft', 'gamma_arena_custom_generator\.build_draft', 'gamma_arena_fight_spec\.canonicalize', 'gamma_arena_fight_validator_v9\.validate', 'session_seed\s*=\s*session\.session_seed', 'fight_index\s*=\s*fight_index', 'layout_hash\s*=\s*gamma_arena_fight_spec\.layout_hash')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current generator RNG isolation protection'
        Path = 'src\gamedata\scripts\gamma_arena_random_generator.script'
        Required = @('CORE_RNG_EPOCH\s*=\s*6', 'MEDICAL_RNG_EPOCH\s*=\s*1', 'local\s+normalized_seed\s*=\s*gamma_arena_rng\.normalize_uint32', 'local\s+normalized_request', 'stream\s*\(\s*normalized_request', 'gamma_arena_number\.is_integer', '"actor_knife"', 'actor\.value\.knife\s*=\s*actor_knife\.value', '"actor_class_pair"', '"actor_weapon"', '"actor_ammo_boxes"', '"actor_outfit"', '"enemy_numeric_rank:"')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current generator RNG isolation protection'
        Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'
        Required = @('random_numeric_rank_stream_is_isolated', 'player_ammo_scaling_is_stream_isolated', 'medical_tuning_does_not_reroll_core_fight', 'longer rosters preserve every indexed prefix draw', 'low_without_actor_ammo')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current ammo scaling protection'
        Path = 'src\gamedata\scripts\gamma_arena_random_generator.script'
        Required = @('PLAYER_AMMO_CHANCE', 'function\s+scaled_ammo_boxes', 'actor_scaled_ammo:', 'magazine_size', 'standard_ammo\.box_size', 'GA_PLAYER_AMMO_SCALE_INVALID', 'final_ammo_boxes')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current ammo scaling protection'
        Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'
        Required = @('player_ammo_scaling_policy_is_uncapped_and_prefix_stable', 'generated_actor_ammo_is_final_and_outside_budget', 'player_ammo_scaling_is_stream_isolated', 'representative_opponent_counts', 'player_ammo_rate_sweep', 'observed rate remains within two percentage points', 'validator_rejects_forged_final_actor_ammo')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current grenade generation protection'
        Path = 'src\gamedata\scripts\gamma_arena_random_generator.script'
        Required = @('gamma_arena_grenade_generator\.generate_actor', 'gamma_arena_grenade_generator\.generate_enemy', 'actor_grenade_count', 'actor_grenade_section:1', 'actor_grenade_section:2', 'enemy_grenade_presence:', 'enemy_grenade_section:', 'actor\.value\.grenades', 'gear\.value\.grenades')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current grenade generation protection'
        Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'
        Required = @('grenade_loadouts_are_deterministic_uncosted_and_prefix_stable', 'validator_rejects_forged_grenade_arrays')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current medical generation protection'
        Path = 'src\gamedata\scripts\gamma_arena_random_generator.script'
        Required = @('gear_cost', 'medical_cost', 'player_gear_budget', 'player_medical_budget', 'gamma_arena_medical_generator\.generate_actor', 'gamma_arena_medical_generator\.allocate_enemies', 'actor_medical_streams', 'enemy_medical_streams')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current medical generation protection'
        Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'
        Required = @('catalog_skips_optional_missing_medicine', 'actor_medical_generation_enforces_budget_and_healer', 'actor_medical_generation_reaches_master_rare', 'enemy_medical_generation_spends_team_budget', 'medical_generation_100000_fights', 'medical_tuning_does_not_reroll_core_fight')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current actor quarantine protection'
        Path = 'src\gamedata\scripts\gamma_arena_catalog.script'
        Required = @('ACTOR_WEAPON_QUARANTINE', 'wpn_dtmdr\s*=\s*true', 'wpn_eft_mts_255_uh2\s*=\s*true', 'actor_weapon_quarantine_v1', 'snapshot\.actor_weapon_list')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current actor quarantine protection'
        Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'
        Required = @('actor_weapon_quarantine_is_exact_and_actor_only', 'GA_ACTOR_WEAPON_QUARANTINED', 'actor generation never selects quarantined MTS-255 UH2')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current affordability and diversity protection'
        Path = 'src\gamedata\scripts\gamma_arena_random_generator.script'
        Required = @('pick_affordable_band', 'global_role_pool', 'role_weapon_pool', 'function\s+select_player_class_pair', 'function\s+player_loadout', 'primary_share_percent', '"actor_class_pair"', '"actor_weapon"', '"actor_ammo_boxes"', '"actor_outfit"')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current affordability and diversity protection'
        Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'
        Required = @('generator_primary_pool_affordability_falls_back', 'weighted_player_class_pair_selection', 'player_class_pair_ignores_concrete_cardinality', 'master_player_class_diversity', 'master_powered_exo_rate_is_rare')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current resolved layout and routing protection'
        Path = 'src\gamedata\scripts\gamma_arena_random_generator.script'
        Required = @('valid_resolved_layout', 'select_spawn_slots', 'assign_routes', 'spawn_slot_id', 'tactical_route', 'primary_share_percent', 'enemy_total_budget')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current resolved layout and routing protection'
        Path = 'src\gamedata\scripts\gamma_arena_fight_validator_v9.script'
        Required = @('GA_FIGHTSPEC_SPAWN_INVALID', 'GA_FIGHTSPEC_ROUTE_INVALID', 'GA_FIGHTSPEC_OPPONENT_SLOT_DUPLICATE', 'used_opponent_slots', 'used_spawns')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current exact runtime ammo protection'
        Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script'
        Required = @('actor creates exact final ordinary rounds', 'runtime does not regenerate the reserve floor')
    },
    [PSCustomObject]@{
        Protection = 'Task 4 current exact runtime ammo protection'
        Path = 'src\gamedata\scripts\gamma_arena_fight_validator_v9.script'
        Required = @('GA_FIGHTSPEC_ITEM_EQUIPMENT_INVALID', 'GA_FIGHTSPEC_AMMO_MISSING', 'GA_FIGHTSPEC_AMMO_ORPHAN', 'GA_FIGHTSPEC_ACTOR_HEALING_MISSING')
    }
)
foreach ($Contract in $Task4CurrentGeneratorContracts) {
    $ContractPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ContractPath) "$($Contract.Protection): current contract file is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ContractPath) {
        $ContractContent = Get-Content -LiteralPath $ContractPath -Raw
        foreach ($Pattern in $Contract.Required) {
            Assert-True ($ContractContent -match $Pattern) "$($Contract.Protection): missing $Pattern in $($Contract.Path)"
        }
    }
}

$Task1RankScriptContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_rank_catalog.script'; Namespace = 'gamma_arena_rank_catalog'; Required = @('(?m)^function\s+load\s*\(', 'max_physical_items_per_participant', 'GA_RANK_PROFILE_RANGE_EMPTY', 'GA_RANK_THRESHOLD_INVALID', 'GA_RANK_LOADOUT_MISSING', 'GA_RANK_ALIAS_MISSING', 'GA_RANK_FACTION_DUPLICATE') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_rank_catalog.script'; Namespace = 'gamma_arena_test_rank_catalog'; Required = @('(?m)^function\s+run\s*\(', 'rank_catalog_exposes_all_exact_ranks', 'rank_catalog_rejects_non_authoritative_physical_item_cap', 'rank_catalog_rejects_non_monotonic_thresholds', 'rank_catalog_enumeration_order_is_stable') }
)

$Task2ItemScriptContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_item_catalog.script'; Namespace = 'gamma_arena_item_catalog'; Required = @('(?m)^function\s+load\s*\(', 'GA_ITEM_CATALOG_PRICE_ANCHOR_MISSING', 'ga-catalog-v10-', 'base_carry_weight', 'max_physical_items_per_participant', 'carry_bonus_mg', 'grenade', 'device', 'candidate_section_name', 'shared_system_sections', 'rank_ids_seen', 'faction_ids_seen', 'pool_seen', 'if not seen\[section\] then') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_item_catalog.script'; Namespace = 'gamma_arena_test_item_catalog'; Required = @('(?m)^function\s+run\s*\(', 'item_catalog_prices_and_classifies_installed_items', 'item_catalog_fingerprint_changes_for_semantic_mutations', 'item_catalog_rejects_unavailable_median_anchors', 'item_catalog_seeds_exact_physical_devices', 'item_catalog_rejects_invalid_physical_devices', 'item_catalog_device_mutations_change_fingerprint', 'item_catalog_prefilters_irrelevant_system_sections', 'item_catalog_reconciles_rank_pools_with_physical_items') }
)

$Task6RandomDraftContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_random_generator.script'; Namespace = 'gamma_arena_random_generator'; Required = @('(?m)^local function\s+build_draft_internal\s*\(\s*session\s*,\s*fight_index\s*,\s*catalog\s*,\s*layout\s*\)', '(?m)^local function\s+valid_build_result\s*\(\s*result\s*\)', '(?m)^function\s+build_draft\s*\(\s*session\s*,\s*fight_index\s*,\s*catalog\s*,\s*layout\s*\)', 'pcall\s*\(\s*build_draft_internal', 'valid_build_result\s*\(\s*result\s*\)', 'GA_RANDOM_CATALOG_INVALID', 'GA_RANDOM_GENERATION_FAILED', 'enemy_numeric_rank:', 'kind\s*=\s*"items"', 'gamma_arena_device_generator\.generate', 'profile\.rank_id', 'profile\.rank_min', 'profile\.rank_max', 'type\s*\(\s*rank_value\s*\)\s*==\s*"table"', 'rank_value\.ok\s*==\s*false', 'variant\.category\s*==\s*nil') },
    [PSCustomObject]@{ Path = 'tests\reference\New-GammaArenaRandomSemanticSnapshot.ps1'; Required = @('golden-random-selections-v9\.txt', 'Read-GaLtx', '10/11/11', 'random_actor_device_v11') },
    [PSCustomObject]@{ Path = 'tests\fixtures\golden-random-selections-v9.txt'; Required = @('seed=0,difficulty=rookie,fight=0', 'seed=1,difficulty=stalker,fight=0', 'seed=3735928559,difficulty=veteran,fight=7', 'seed=4294967295,difficulty=master,fight=31', 'device:') }
)
$Task6ArtifactsPresent = Test-Path -LiteralPath (Join-Path $RepoRoot 'tests\reference\New-GammaArenaRandomSemanticSnapshot.ps1')
if ($Task6ArtifactsPresent) {
    foreach ($Contract in $Task6RandomDraftContracts) {
        $ContractPath = Join-Path $RepoRoot $Contract.Path
        Assert-True (Test-Path -LiteralPath $ContractPath) "Task 6 random draft contract is missing: $($Contract.Path)"
        if (Test-Path -LiteralPath $ContractPath) {
            $ContractContent = Get-Content -LiteralPath $ContractPath -Raw
            foreach ($Pattern in $Contract.Required) {
                Assert-True ($ContractContent -match $Pattern) "Task 6 random draft marker is missing from $($Contract.Path): $Pattern"
            }
        }
    }
    $Task6ReferenceContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'tests\reference\New-GammaArenaRandomSemanticSnapshot.ps1') -Raw
    Assert-True ($Task6ReferenceContent -notmatch 'gamma_arena_(?:random_)?generator\.script') 'Task 6 semantic reference must not read Lua generator source.'
    $Task6SnapshotLines = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'tests\fixtures\golden-random-selections-v9.txt') | Where-Object { $_ -and -not $_.StartsWith('#') })
    Assert-True ($Task6SnapshotLines.Count -eq 4) 'Task 6 semantic snapshot must contain exactly four reviewed random scenarios.'
    $Task6GeneratorTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_generator.script') -Raw
    Assert-True ($Task6GeneratorTests -match [regex]::Escape('random_builder_skips_items_outside_universal_catalog')) `
        'Task 6 Random universal-catalog regression is missing.'
    $Task6RandomGenerator = Get-Content -LiteralPath `
        (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_random_generator.script') -Raw
    foreach ($Marker in @('random_catalog_view', 'catalog_item_matches', '#view.device_list ~= 4')) {
        Assert-True ($Task6RandomGenerator -match [regex]::Escape($Marker)) `
            "Task 6 Random universal-catalog boundary is missing: $Marker"
    }
    foreach ($Marker in @('random_draft_matches_frozen_semantic_snapshot', 'random_numeric_rank_stream_is_isolated', 'random_draft_pipeline_canonicalizes_and_strictly_validates', 'random_draft_malformed_inputs_are_total_results', 'random_draft_nested_malformed_and_throwing_inputs_are_total_results', 'random_draft_malformed_dependency_results_are_normalized', 'random_draft_accepts_unclassified_bonus_ammo', 'catalog_enumerates_effective_system_once_per_load', 'catalog_enumeration_failure_is_memoized', 'bonus_ammo.requested_category', 'bonus_ammo.resolved_category', 'bonus_ammo.boxes')) {
        Assert-True ($Task6GeneratorTests -match [regex]::Escape($Marker)) "Task 6 executable draft test is missing: $Marker"
    }
    $Task6CatalogLoader = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script') -Raw
    Assert-True ($Task6CatalogLoader -match 'memoized_system_factory') 'Catalog loader must enumerate the effective system once per load.'
    Assert-True ($Task6CatalogLoader -match 'pcall\(factory\.enumerate_system_sections\)') 'Catalog loader must memoize failed effective-system enumeration attempts.'
    Assert-True ($Task6CatalogLoader -match 'if\s+not\s+succeeded\s+then\s+error') 'Catalog loader must replay a memoized effective-system enumeration failure.'
    Assert-True ($Task6CatalogLoader -match 'shared_system_sections') 'Catalog loader must share the memoized system enumeration with the physical item catalog.'
    $Task7RandomPipelineFixture = [regex]::Match($Task6GeneratorTests, '(?s)local function random_draft_catalogs\(\).*?local function random_draft_semantics').Value
    Assert-True ($Task7RandomPipelineFixture.Contains('snapshot.fingerprint = "ga-catalog-v10-random-pipeline"')) 'Task 7 positive random pipeline fixture must use the exact v10 catalog fingerprint.'
    Assert-True ($Task7RandomPipelineFixture -notmatch 'ga-catalog-v[1-9]-') 'Task 7 positive random pipeline fixture must not use a retired catalog fingerprint.'
    $ActiveGenerator = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_generator.script') -Raw
    Assert-True ($ActiveGenerator -match 'gamma_arena_fight_builder\.generate' -and $ActiveGenerator -match 'gamma_arena_fight_spec\.stable_encode') 'Task 7 must retain the thin universal generator facade.'
}

$Task7CurrentArtifacts = @(
    'src\gamedata\scripts\gamma_arena_fight_builder.script',
    'src\gamedata\scripts\gamma_arena_fight_validator_v9.script',
    'schemas\fight-spec-v9.md',
    'tests\fixtures\golden-fights-v9.txt',
    'tests\fixtures\golden-random-selections-v9.txt'
)

$Task8CustomContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_custom_config.script'; Namespace = 'gamma_arena_custom_config'; Required = @('(?m)^function\s+validate\s*\(', '(?m)^function\s+validate_weapon_pool\s*\(', '(?m)^function\s+prewarm_catalog_rank_pools\s*\(', '(?m)^function\s+budget\s*\(', '(?m)^function\s+totals\s*\(', 'primary_weapons', 'secondary_weapons', 'GA_CUSTOM_ITEM_REQUIRED', 'GA_CUSTOM_GRENADE_LIMIT', 'GA_CUSTOM_EQUIPMENT_QUANTITY', 'GA_CUSTOM_WEAPON_POOL_INVALID', 'second_grenade_price_multiplier', 'max_physical_items_per_participant', 'weight_limit_mg', 'weapon_records_by_catalog', 'successful_pool_by_catalog', '__mode\s*=\s*"k"', 'valid_pool_prerequisites', 'cached_pool_validation') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_custom_codec.script'; Namespace = 'gamma_arena_custom_codec'; Required = @('(?m)^function\s+keys\s*\(', '(?m)^function\s+encode\s*\(', '(?m)^function\s+decode\s*\(', 'dense_length', 'exact_fields', 'canonical_integer', 'CONFIG_FIELDS', 'ROSTER_FIELDS', 'ITEM_FIELDS', 'GA_CUSTOM_CODEC_TRAILING_KEY', 'roster_count', 'actor_item_count', 'equipped_slot') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_custom_config.script'; Namespace = 'gamma_arena_test_custom_config'; Required = @('(?m)^function\s+run\s*\(', 'custom_config_rejects_roster_catalog_and_shape_matrix', 'custom_config_distinguishes_empty_inventory_from_entry_overflow', 'custom_config_rejects_selected_empty_rank_weapon_pool', 'custom_config_rejects_equipment_compatibility_and_budget_matrix', 'custom_config_rejects_non_unit_physical_equipment', 'custom_config_preserves_legitimate_inventory_stacks', 'custom_config_grenade_order_is_semantic', 'custom_codec_round_trip_preserves_bounded_order', 'custom_codec_rejects_sparse_and_oversized_shapes', 'custom_codec_encode_rejects_unknown_fields_and_malformed_scalars', 'custom_codec_encode_uses_canonical_decimal_quantities', 'custom_config_reuses_successful_immutable_rank_pool_validation', 'custom_config_does_not_cache_rank_pool_failures_or_context', 'custom_config_malformed_pool_inputs_bypass_cache_and_preserve_context', 'custom_setup_model_rank_callbacks_reuse_all_prevalidated_profiles', 'custom_setup_model_snapshots_reuse_committed_derived_state') }
)

foreach ($Contract in $Task8CustomContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 8 custom contract is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        $NamespacePattern = [regex]::Escape($Contract.Namespace)
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 8 script must not create a self-named namespace table: $($Contract.Path)"
        foreach ($Pattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $Pattern) "Task 8 custom marker is missing from $($Contract.Path): $Pattern"
        }
    }
}

$Task8CustomTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_custom_config.script') -Raw
foreach ($Name in @('custom_config_reuses_successful_immutable_rank_pool_validation','custom_config_does_not_cache_rank_pool_failures_or_context','custom_config_malformed_pool_inputs_bypass_cache_and_preserve_context','custom_setup_model_rank_callbacks_reuse_all_prevalidated_profiles')) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($Task8CustomTests, $Registration)).Count -eq 1) "Task 8 cache case must be registered exactly once: $Name"
}

$Task8CustomSource = Get-Content -LiteralPath (Join-Path $RepoRoot $Task8CustomContracts[0].Path) -Raw
$Task8PoolPrerequisiteBlock = [regex]::Match($Task8CustomSource,
    '(?ms)^local\s+function\s+valid_pool_prerequisites\s*\(\s*profile\s*,\s*catalog\s*\).*?^end\s*$').Value
$Task8SharedPrerequisites = $Task8PoolPrerequisiteBlock -match `
    '(?s)return\s+type\(profile\)\s*==\s*"table"\s+and\s+type\(catalog\)\s*==\s*"table"\s+and\s+type\(catalog\.items\)\s*==\s*"table"\s+and\s+type\(catalog\.ammo\)\s*==\s*"table"\s+and\s+type\(catalog\.weapon_list\)\s*==\s*"table"'
Assert-True $Task8SharedPrerequisites `
    'Task 8 pool caches must share the complete profile and catalog prerequisite predicate.'

$Task8PoolCacheBlock = [regex]::Match($Task8CustomSource,
    '(?ms)^local\s+function\s+cached_pool_validation\s*\(.*?^end\s*$').Value
$Task8PoolTypeGate = $Task8PoolCacheBlock.IndexOf('if not valid_pool_prerequisites(profile, catalog) then')
$Task8PoolBypass = $Task8PoolCacheBlock -match `
    'if\s+not\s+valid_pool_prerequisites\(profile,\s*catalog\)\s+then\s*return\s+validate_weapon_pool_internal\(profile,\s*catalog,\s*context\)\s*end'
$Task8PoolCacheAccess = $Task8PoolCacheBlock.IndexOf('successful_pool_by_catalog[catalog]')
Assert-True ($Task8PoolBypass -and $Task8PoolTypeGate -ge 0 -and $Task8PoolCacheAccess -gt $Task8PoolTypeGate) `
    'Task 8 pool cache must apply shared prerequisites before cache access.'

$Task8PoolInternalBlock = [regex]::Match($Task8CustomSource,
    '(?ms)^local\s+function\s+validate_weapon_pool_internal\s*\(.*?^end\s*$').Value
$Task8PoolPrerequisiteGate = $Task8PoolInternalBlock.IndexOf('if not valid_pool_prerequisites(profile, catalog) then')
$Task8WeaponRecordsAccess = $Task8PoolInternalBlock.IndexOf('weapon_records(catalog)')
Assert-True ($Task8PoolPrerequisiteGate -ge 0 -and $Task8WeaponRecordsAccess -gt $Task8PoolPrerequisiteGate) `
    'Task 8 pool validation must apply shared prerequisites before reading cached weapon records.'

$Task8RankCallbackCase = [regex]::Match($Task8CustomTests,
    '(?ms)^local\s+function\s+custom_setup_model_rank_callbacks_reuse_all_prevalidated_profiles\(\).*?^end\s*$').Value
foreach ($Marker in @('for\s+index\s*=\s*1\s*,\s*512', 'gamma_arena_custom_setup_model\.new',
    'model:set_count\s*\(\s*10\s*\)', 'model:set_rank\s*\(\s*1\s*,\s*rank_id\s*\)',
    'model:status_snapshot\s*\(\s*\)', 'operations\.profile_reads\s*,\s*0', 'operations\.weapon_reads\s*,\s*0')) {
    Assert-True ($Task8RankCallbackCase -match $Marker) "Rank callback operation-count regression is missing: $Marker"
}
Assert-True ($Task8RankCallbackCase -match 'operations\.profile_reads\s*,\s*operations\.weapon_reads\s*=\s*0\s*,\s*0') `
    'Rank callback regression must reset operation counters immediately before the real model call graph.'

$Task8ItemCatalogSource = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_item_catalog.script') -Raw
$Task8CatalogSource = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script') -Raw
$Task8ModelSource = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_setup_model.script') -Raw
Assert-True ($Task8ItemCatalogSource -match 'reconciled_pool_records_by_catalog\s*=\s*setmetatable\(\{\},\s*\{\s*__mode\s*=\s*"k"') `
    'Reconciled rank-pool proofs must be weakly keyed by final catalog identity.'
Assert-True ($Task8ItemCatalogSource -match 'function\s+reconciled_weapon_pool\s*\(\s*catalog\s*,\s*profile\s*\)') `
    'Item-catalog reconciliation must expose exact catalog/profile identity proofs.'
$Task8PrimerBlock = [regex]::Match($Task8CustomSource,
    '(?ms)^function\s+prewarm_catalog_rank_pools\(.*?^end\s*$').Value
foreach ($Marker in @('catalog\.faction_ids', 'catalog\.rank_ids', 'reconciled_weapon_pool\s*\(\s*catalog\s*,\s*profile\s*\)',
    'cached_pool_validation\s*\(\s*profile\s*,\s*catalog', 'successful_pool_by_catalog\[catalog\]', 'summary\.complete')) {
    Assert-True ($Task8PrimerBlock -match $Marker) "Catalog rank-pool primer is missing: $Marker"
}
$Task8CatalogLoadBlock = [regex]::Match($Task8CatalogSource, '(?ms)^local\s+function\s+load_impl\(.*?^end\s*$').Value
Assert-True ($Task8CatalogLoadBlock.IndexOf('gamma_arena_custom_config.prewarm_catalog_rank_pools') -gt
    $Task8CatalogLoadBlock.IndexOf('gamma_arena_item_catalog.load')) `
    'Runtime catalog load must prewarm rank profiles after item reconciliation.'
$Task8ModelNewBlock = [regex]::Match($Task8ModelSource, '(?ms)^function\s+new\(.*?^end\s*$').Value
Assert-True ($Task8ModelNewBlock -match 'gamma_arena_custom_config\.prewarm_catalog_rank_pools\s*\(\s*catalog\s*\)') `
    'Direct model construction must prevalidate rank pools outside count/rank callbacks.'

$Task8SessionContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script') -Raw
foreach ($Marker in @('launch_schema_version', 'launch_generator_version', 'launch_catalog_revision', 'launch_catalog_fingerprint', 'launch_custom_', 'gamma_arena_custom_codec.keys', 'gamma_arena_custom_codec.decode', 'persisted_keys_absent')) {
    Assert-True ($Task8SessionContent -match [regex]::Escape($Marker)) "Task 8 session persistence is missing: $Marker"
}
$Task8MigrationContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_migrations.script') -Raw
Assert-True ($Task8MigrationContent -match 'gamma_arena_custom_codec\.keys\s*\(\s*"launch_custom_"\s*\)') 'Task 8 migration cleanup must include every bounded custom launch key.'
$Task8RuntimeTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
Assert-True ($Task8RuntimeTests -match 'runtime_custom_start_validates_before_launch_mutation') 'Task 8 runtime tests must prove validation precedes launch mutation.'
$Task8MigrationTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_migrations.script') -Raw
foreach ($Marker in @('custom_launch_round_trip_is_bounded_ordered_and_catalog_bound', 'custom_launch_rejects_mixed_schema_and_recipe_keys', 'custom_launch_faults_cover_indexed_key_range')) {
    Assert-True ($Task8MigrationTests -match [regex]::Escape($Marker)) "Task 8 migration tests must cover $Marker."
}

$Task9CustomContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_custom_setup_model.script'; Namespace = 'gamma_arena_custom_setup_model'; Required = @('(?m)^function\s+new\s*\(', '(?m)^local\s+function\s+commit_allowing_incomplete_budget\s*\(', '(?m)^local\s+function\s+refresh_derived\s*\(', '(?m)^local\s+function\s+accept_candidate\s*\(', '(?m)^local\s+function\s+derived_values\s*\(', 'current_validation', 'current_budget', 'current_totals', 'function\s+Model:set_faction', 'function\s+Model:set_count', 'function\s+Model:set_rank', 'function\s+Model:add_item', 'function\s+Model:increment_item', 'function\s+Model:decrement_item', 'function\s+Model:remove_item', 'function\s+Model:equip', 'function\s+Model:unequip', 'function\s+Model:preview_add_one', 'function\s+Model:add_one', 'function\s+Model:remove_one', 'function\s+Model:equip_replacing', 'function\s+Model:snapshot', 'function\s+Model:validation', 'gamma_arena_custom_config\.validate', 'gamma_arena_custom_config\.validate_draft', 'max_entries', 'max_physical_items_per_participant', 'selected_grenades', 'effective_price', 'last_operation') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_custom_setup_presenter.script'; Namespace = 'gamma_arena_custom_setup_presenter'; Required = @('(?m)^function\s+new\s*\(', 'function\s+Presenter:project', 'function\s+Presenter:refresh_affordability', 'function\s+Presenter:readiness', '(?m)^local\s+function\s+projection_failure\s*\(', '(?m)^function\s+status_presentation\s*\(', '(?m)^function\s+format_status\s*\(', 'preview_add_one', 'price_asc', 'name_asc', 'catalog_page_count', 'disabled_reason', 'st_gamma_arena_custom_readiness_healing') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_ui_faction_picker.script'; Namespace = 'gamma_arena_ui_faction_picker'; Required = @('(?m)^function\s+new\s*\(', '(?m)^function\s+layout\s*\(', '(?m)^function\s+texture_id\s*\(', 'function\s+Picker:open', 'function\s+Picker:close', 'function\s+Picker:is_open', 'function\s+Picker:select', 'MAX_FACTIONS\s*=\s*13', 'COLUMN_COUNT\s*=\s*4', 'GA_CUSTOM_FACTION_UNKNOWN', 'ui_mm_faction_', 'ui_new_game_flair_zombied') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_ui_custom.script'; Namespace = 'gamma_arena_ui_custom'; Required = @('class\s+"UICustom"\s+\(CUIScriptWnd\)', '(?m)^function\s+create\s*\(', '(?m)^function\s+project\s*\(', '(?m)^function\s+submit\s*\(', '(?m)^function\s+dispatch_transfer\s*\(', '(?m)^function\s+dispatch_drop\s*\(', '(?m)^function\s+dispatch_equip\s*\(', 'gamma_arena_custom_setup_presenter\.new', 'utils_ui\.UICellContainer', 'inventory_container', 'loadout_container', 'gamma_arena_custom_config\.validate', 'schema_version\s*=\s*2', 'generation_recipe\s*=\s*"custom"', 'EDIT_TEXT_COMMIT', 'LIST_ITEM_SELECT', 'OnCatalogSearch', 'OnCatalogFilter', 'OnCatalogSort', 'On_CC_Mouse1', 'On_CC_DragDrop', 'dispatch_transfer', 'dispatch_drop', 'equip_replacing', 'operation_error_code', 'summary_code', 'x2', 'start_button:Enable', 'GA_DEBUG_CUSTOM_CATALOG_BEGIN', 'GA_DEBUG_CUSTOM_CATALOG_RESULT', 'GA_DEBUG_CUSTOM_REBUILD_BEGIN', 'GA_DEBUG_CUSTOM_REBUILD_RESULT') }
)
foreach ($Contract in $Task9CustomContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 9 custom UI contract is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        $NamespacePattern = [regex]::Escape($Contract.Namespace)
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 9 script must not create a self-named namespace table: $($Contract.Path)"
        foreach ($Pattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $Pattern) "Task 9 marker is missing from $($Contract.Path): $Pattern"
        }
    }
}

$Task9StartContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_start.script') -Raw
foreach ($Marker in @('custom_mode', 'function UIStart:OnCustom', 'gamma_arena_ui_custom.create', 'GA_DEBUG_CUSTOM_CLICK', 'GA_DEBUG_CUSTOM_CREATE_RESULT')) {
    Assert-True ($Task9StartContent -match [regex]::Escape($Marker)) "Task 9 start-mode routing is missing: $Marker"
}
$Task9UiDiagnosticPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_custom.script'
$Task9UiDiagnostic = Get-Content -LiteralPath $Task9UiDiagnosticPath -Raw
Assert-True ($Task9UiDiagnostic -match '(?m)^function\s+apply_catalog_result\s*\(') 'Task 9 Custom UI must preserve primary catalog failures in the visible summary.'
foreach ($Marker in @(
    'CATALOG_PAGE_SIZE = 80', 'catalog_page_count', 'catalog_has_previous',
    'function UICustom:OnCatalogPrevious', 'function UICustom:OnCatalogNext',
    'self.catalog_state.page = 1'
)) {
    Assert-True ($Task9UiDiagnostic -match [regex]::Escape($Marker)) `
        "Task 9 bounded catalog UI is missing: $Marker"
}
$Task9PaginationCase = [regex]::Match($Task8RuntimeTests, 'local\s+function\s+runtime_custom_ui_catalog_projection_is_bounded_and_complete\(\)[\s\S]*?\r?\nend').Value
Assert-True ($Task9PaginationCase -match 'for\s+offset,\s*cell\s+in\s+ipairs\(view\.catalog_cells\)' -and
    $Task9PaginationCase -match 'catalog\.categories\.weapon\s*\[\s*\(page\s*-\s*1\)\s*\*\s*80\s*\+\s*offset\s*\]') 'Bounded Custom catalog regression must assert exact source order at every page and cell offset.'
$Task9StartXmlPath = Join-Path $RepoRoot 'src\gamedata\configs\ui\gamma_arena_start.xml'
[xml]$Task9StartXml = Get-Content -LiteralPath $Task9StartXmlPath -Raw
Assert-True ($null -ne $Task9StartXml.SelectSingleNode("//*[local-name()='custom_mode']")) 'Task 9 start XML must expose Custom mode.'
$Task9CustomXmlPath = Join-Path $RepoRoot 'src\gamedata\configs\ui\gamma_arena_custom.xml'
Assert-True (Test-Path -LiteralPath $Task9CustomXmlPath) 'Task 9 custom UI XML is missing.'
if (Test-Path -LiteralPath $Task9CustomXmlPath) {
    [xml]$Task9CustomXml = Get-Content -LiteralPath $Task9CustomXmlPath -Raw
    $Task9KnownEngineFonts = @('graffiti19','graffiti22','graffiti32','letterica16','letterica18')
    $Task9CustomFontIds = @($Task9CustomXml.SelectNodes('//@font') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    foreach ($FontId in $Task9CustomFontIds) {
        Assert-True ($Task9KnownEngineFonts -ccontains $FontId) ('Task 9 custom UI XML uses unknown engine font: ' + $FontId)
    }
    foreach ($Id in @('gamma_arena_custom','faction_button','count','seed','device','inventory_panel','loadout_panel','inventory_container','loadout_container',
        'catalog_search','catalog_filter','catalog_sort','points_available','points_used','weight','weight_limit',
        'readiness_outfit','readiness_knife','readiness_weapon','readiness_ammo','readiness_healing',
        'validation','start','random','back')) {
        Assert-True ($null -ne $Task9CustomXml.SelectSingleNode("//*[local-name()='$Id']")) "Task 9 custom UI XML is missing control $Id"
    }
    foreach ($Id in @('opponents_caption','conditions_caption','faction_button','faction_icon','faction_label','count_label',
        'seed_label','seed_helper','device_label','device_helper','roster_caption','catalog_search_label','readiness_caption',
        'faction_popup','faction_popup_blocker','faction_popup_frame','faction_cancel')) {
        Assert-True ($null -ne $Task9CustomXml.SelectSingleNode("//*[local-name()='$Id']")) `
            "Custom UX XML is missing explicit setup control $Id"
    }
    foreach ($Index in 1..13) {
        Assert-True ($null -ne $Task9CustomXml.SelectSingleNode("//*[local-name()='faction_slot_$Index']")) `
            "Custom faction picker XML is missing bounded slot $Index"
    }
    foreach ($Id in @('catalog_previous','catalog_page','catalog_next')) {
        Assert-True ($null -ne $Task9CustomXml.SelectSingleNode("//*[local-name()='$Id']")) `
            "Task 9 Custom pagination control is missing: $Id"
    }
    foreach ($Index in 1..10) {
        Assert-True ($null -ne $Task9CustomXml.SelectSingleNode("//*[local-name()='roster_row_$Index']")) "Task 9 custom UI XML is missing roster row $Index"
        Assert-True ($null -ne $Task9CustomXml.SelectSingleNode("//*[local-name()='rank_$Index']")) "Task 9 custom UI XML is missing rank selector $Index"
    }
    $Task9InventoryContainer = $Task9CustomXml.SelectSingleNode("//*[local-name()='inventory_container']")
    $Task9LoadoutContainer = $Task9CustomXml.SelectSingleNode("//*[local-name()='loadout_container']")
    $Task9CatalogControls = $Task9CustomXml.SelectSingleNode("//*[local-name()='catalog_controls']")
    foreach ($Id in @('inventory_panel','loadout_panel')) {
        $Panel = $Task9CustomXml.SelectSingleNode("//*[local-name()='$Id']")
        $Texture = if ($null -eq $Panel) { $null } else { $Panel.SelectSingleNode("*[local-name()='texture']") }
        Assert-True ($null -ne $Panel -and $Panel.GetAttribute('stretch') -eq '1') `
            "Task 9 Custom $Id must be a stretchable underlay."
        Assert-True ($null -ne $Texture -and $Texture.InnerText -eq 'ui_inGame2_workshop_upgrade_inv') `
            "Task 9 Custom $Id must use the stock GAMMA inventory texture."
    }
    if ($null -ne $Task9InventoryContainer -and $null -ne $Task9LoadoutContainer) {
        Assert-True ([int]$Task9InventoryContainer.width -eq [int]$Task9LoadoutContainer.width) `
            'Task 9 Custom inventory and loadout panels must have equal width.'
        Assert-True ([int]$Task9InventoryContainer.height -eq [int]$Task9LoadoutContainer.height) `
            'Task 9 Custom inventory and loadout panels must have equal height.'
        Assert-True ($null -ne $Task9CatalogControls -and
            [int]$Task9CatalogControls.x -eq [int]$Task9InventoryContainer.x) `
            'Task 9 Custom catalog controls must align with the left inventory catalog.'
    }
}
foreach ($Locale in @('eng','rus')) {
    $Task9Locale = Get-Content -LiteralPath (Join-Path $RepoRoot "src\gamedata\configs\text\$Locale\st_gamma_arena.xml") -Raw
    foreach ($StringId in @('st_gamma_arena_custom_mode','st_gamma_arena_custom_title','st_gamma_arena_custom_faction','st_gamma_arena_custom_count','st_gamma_arena_custom_seed','st_gamma_arena_custom_budget','st_gamma_arena_custom_spent','st_gamma_arena_custom_remaining','st_gamma_arena_custom_weight','st_gamma_arena_custom_weight_limit','st_gamma_arena_custom_random','st_gamma_arena_custom_category_grenade')) {
        Assert-True ($Task9Locale -match ('id="' + [regex]::Escape($StringId) + '"')) "Task 9 $Locale localization is missing $StringId"
    }
    if ($Locale -eq 'eng') {
        [xml]$Task12LocaleDocument = $Task9Locale
        $Task12HintNode = $Task12LocaleDocument.SelectSingleNode('//string[@id="st_gamma_arena_custom_selected_hint"]/text')
        $Task12Hint = if ($null -eq $Task12HintNode) { '' } else { $Task12HintNode.InnerText }
        Assert-True ($Task12Hint -match '(?i)decrements? (?:the )?quantity by one' -and $Task12Hint -match '(?i)removes?.*quantity (?:is|equals) one') 'Task 12 ENG selected-loadout hint must distinguish stack decrement from quantity-one removal.'
    }
    else {
        $Task12HintMatch = [regex]::Match($Task9Locale, '(?s)<string id="st_gamma_arena_custom_selected_hint"><text>(.*?)</text></string>')
        $Task12HintRaw = if ($Task12HintMatch.Success) { $Task12HintMatch.Groups[1].Value } else { '' }
        $Task12Decrease = '&#x0443;&#x043C;&#x0435;&#x043D;&#x044C;&#x0448;&#x0430;&#x0435;&#x0442;'
        $Task12Quantity = '&#x043A;&#x043E;&#x043B;&#x0438;&#x0447;&#x0435;&#x0441;&#x0442;&#x0432;&#x043E;'
        $Task12Remove = '&#x0443;&#x0434;&#x0430;&#x043B;&#x044F;&#x0435;&#x0442;'
        Assert-True ($Task12HintRaw.Contains($Task12Decrease) -and $Task12HintRaw.Contains($Task12Quantity) -and $Task12HintRaw.Contains($Task12Remove) -and $Task12HintRaw.Contains(' 1')) 'Task 12 RUS selected-loadout hint must distinguish stack decrement from quantity-one removal.'
    }
}
$Task9CustomTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_custom_config.script') -Raw
foreach ($Name in @('custom_setup_model_preserves_order_and_recalculates_budget','custom_setup_model_progressively_assembles_valid_equipment_and_categories','custom_setup_model_rejects_masked_semantic_candidates_atomically','custom_setup_model_edits_stack_quantities_without_duplicates','custom_setup_model_one_unit_commands_are_atomic','custom_setup_model_auto_equips_and_replaces_weapon_atomically','custom_setup_model_preserves_overbudget_inventory_for_repair','custom_setup_model_snapshots_reuse_committed_derived_state','custom_setup_model_grenade_selection_removal_and_reorder_are_semantic')) {
    Assert-True ($Task9CustomTests -match [regex]::Escape($Name)) "Task 9 model tests must cover $Name"
}
$DerivedStateCase = 'custom_setup_model_snapshots_reuse_committed_derived_state'
$DerivedStateRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($DerivedStateCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($DerivedStateCase) + '\s*\}'
Assert-True (([regex]::Matches($Task9CustomTests, $DerivedStateRegistration)).Count -eq 1) `
    'Custom derived-state cache regression must be registered exactly once.'
$Task9RuntimeTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Name in @('runtime_custom_ui_launch_projection_is_authoritative','runtime_custom_ui_grenade_projection_disables_cells_at_limit','runtime_custom_ui_projects_rejected_operation_until_success','runtime_custom_ui_rebuilds_catalog_left_and_selected_right','runtime_custom_presenter_filters_sorts_and_pages_deterministically','runtime_custom_presenter_preview_and_readiness_are_authoritative','runtime_composed_catalog_supports_first_custom_item_edit')) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($Task9RuntimeTests, $Registration)).Count -eq 1) "Task 9 runtime case must be registered exactly: $Name"
}
$PresenterPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_setup_presenter.script'
$PresenterContent = Get-Content -LiteralPath $PresenterPath -Raw
$PresenterLessBlock = [regex]::Match($PresenterContent, '(?ms)^local\s+function\s+less\s*\(.*?^end\s*$').Value
Assert-True ($PresenterLessBlock -match [regex]::Escape('if descending then return left_value > right_value end')) `
    'Custom descending sort must use an explicit branch so the false comparison cannot fall through to ascending.'
Assert-True ($PresenterLessBlock -notmatch 'return\s+descending\s+and') `
    'Custom descending sort must not use Lua and/or as a ternary comparator.'
$PresenterSortCase = [regex]::Match($Task9RuntimeTests, '(?ms)^local\s+function\s+runtime_custom_presenter_filters_sorts_and_pages_deterministically\(\).*?^end\s*$').Value
foreach ($SortId in @('price_desc','name_desc')) {
    Assert-True ($PresenterSortCase -match ('sort\s*=\s*"' + [regex]::Escape($SortId) + '"')) `
        "Custom presenter regression must execute $SortId through the real project path."
}
$ReadableCustomCases = @(
    'runtime_custom_ui_initializes_one_authoritative_faction',
    'runtime_custom_ui_distinguishes_incomplete_and_failed_status',
    'runtime_custom_faction_picker_layout_and_textures_are_bounded',
    'runtime_custom_faction_picker_select_and_cancel_are_atomic',
    'runtime_custom_ui_applies_confirmed_faction_atomically',
    'runtime_custom_ui_escape_cancels_picker_before_navigation',
    'runtime_custom_ui_readiness_guidance_tracks_launch_state'
)
foreach ($Name in $ReadableCustomCases) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($Task9RuntimeTests, $Registration)).Count -eq 1) `
        "Readable Custom runtime case must be registered exactly: $Name"
}
$HoverCase = 'runtime_custom_ui_formats_ap_and_routes_native_hover'
$HoverRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($HoverCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($HoverCase) + '\s*\}'
Assert-True (([regex]::Matches($Task9RuntimeTests, $HoverRegistration)).Count -eq 1) `
    "Readable Custom runtime case must be registered exactly: $HoverCase"
$TransferCase = 'runtime_custom_ui_click_and_drag_dispatch_identical_commands'
$TransferRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($TransferCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($TransferCase) + '\s*\}'
Assert-True (([regex]::Matches($Task9RuntimeTests, $TransferRegistration)).Count -eq 1) `
    "Readable Custom runtime case must be registered exactly: $TransferCase"
$ReadableCustomUi = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_custom.script') -Raw
$CustomIntegrationMarkers = @('self.catalog_state =','self.presenter = gamma_arena_custom_setup_presenter.new',
    'self.inventory_container = utils_ui.UICellContainer','self.loadout_container = utils_ui.UICellContainer',
    'function rebuild_panels',
    'container.disable_drag = false','container.disable_info = false','function UICustom:OnCatalogSearch',
    'function UICustom:OnCatalogFilter','function UICustom:OnCatalogSort','function UICustom:On_CC_DragDrop',
    'self.inventory_container:IsCursorOverWindow()','self.loadout_container:IsCursorOverWindow()')
foreach ($Marker in $CustomIntegrationMarkers) {
    Assert-True ($ReadableCustomUi -match [regex]::Escape($Marker)) "Two-panel Custom integration is missing $Marker"
}
$GroupedControlMarkers = @(
    'self.enemy_setup = self.xml:InitStatic("gamma_arena_custom:enemy_setup", self.root)',
    'self.roster_panel = self.xml:InitStatic("gamma_arena_custom:roster", self.root)',
    'self.catalog_controls = self.xml:InitStatic("gamma_arena_custom:catalog_controls", self.root)',
    'self.footer_panel = self.xml:InitStatic("gamma_arena_custom:footer", self.root)',
    'self.opponents_caption = self.xml:InitStatic("gamma_arena_custom:enemy_setup:opponents_caption", self.enemy_setup)',
    'self.conditions_caption = self.xml:InitStatic("gamma_arena_custom:enemy_setup:conditions_caption", self.enemy_setup)',
    'self.faction_button = self.xml:Init3tButton("gamma_arena_custom:enemy_setup:faction_button", self.enemy_setup)',
    'self.faction_icon = self.xml:InitStatic("gamma_arena_custom:enemy_setup:faction_icon", self.enemy_setup)',
    'self.seed_helper = self.xml:InitStatic("gamma_arena_custom:enemy_setup:seed_helper", self.enemy_setup)',
    'self.device_helper = self.xml:InitStatic("gamma_arena_custom:enemy_setup:device_helper", self.enemy_setup)',
    'self.roster_caption = self.xml:InitStatic("gamma_arena_custom:roster:roster_caption", self.roster_panel)',
    'self.catalog_search_label = self.xml:InitStatic("gamma_arena_custom:catalog_controls:catalog_search_label", self.catalog_controls)',
    'self.readiness_caption = self.xml:InitTextWnd("gamma_arena_custom:footer:readiness_caption", self.footer_panel)',
    '"gamma_arena_custom:catalog_controls:catalog_search", self.catalog_controls',
    'self.xml:InitStatic(row_path, self.roster_panel)',
    '"gamma_arena_custom:footer:weight", self.footer_panel'
)
foreach ($Marker in $GroupedControlMarkers) {
    Assert-True ($ReadableCustomUi -match [regex]::Escape($Marker)) `
        "Custom grouped control is not anchored to its XML parent: $Marker"
}
$DispatchTransferBlock = [regex]::Match($ReadableCustomUi, '(?ms)^function\s+dispatch_transfer\s*\(.*?^end\s*$').Value
foreach ($Marker in @(
    'direction == "inventory_to_loadout" and callable(model, "add_one")',
    'direction == "loadout_to_inventory" and callable(model, "remove_one")'
)) {
    Assert-True ($DispatchTransferBlock -match [regex]::Escape($Marker)) `
        "Custom transfer direction must spend or refund AP through the correct command: $Marker"
}
foreach ($Marker in @(
    'self.inventory_panel = self.xml:InitStatic("gamma_arena_custom:inventory_panel", self.root)',
    'self.loadout_panel = self.xml:InitStatic("gamma_arena_custom:loadout_panel", self.root)',
    'self.inventory_caption = self.xml:InitStatic("gamma_arena_custom:inventory_caption", self.root)',
    'self.loadout_caption = self.xml:InitStatic("gamma_arena_custom:loadout_caption", self.root)'
)) {
    Assert-True ($ReadableCustomUi -match [regex]::Escape($Marker)) `
        "Custom item panel is not initialized: $Marker"
}
Assert-True ($ReadableCustomUi -notmatch 'TransferItem') `
    'Two-panel Custom UI must rebuild from the model instead of transferring cells optimistically.'
$RebuildPanelsBlock = [regex]::Match($ReadableCustomUi, '(?ms)^function\s+rebuild_panels\(.*?^end\s*$').Value
Assert-True ($RebuildPanelsBlock -match 'rebuild_container\(inventory_container,\s*view\.catalog_cells,\s*false\)') `
    'Left inventory must render catalog cells.'
Assert-True ($RebuildPanelsBlock -match 'rebuild_container\(loadout_container,\s*view\.selected_cells,\s*true\)') `
    'Right loadout must render selected cells.'
Assert-True ($ReadableCustomUi -match 'rebuild_panels\(self\.inventory_container,\s*self\.loadout_container,\s*view\)') `
    'Live Custom rebuild must use the behavior-tested panel ownership path.'
$CustomEquipClickBlock = [regex]::Match($ReadableCustomUi, '(?ms)^function\s+UICustom:On_CC_Mouse2\(.*?^end\s*$').Value
Assert-True ($CustomEquipClickBlock -match 'container_id\s*~=\s*"loadout"') `
    'Right-click equip must operate on the selected right loadout.'
$RebuildContainerBlock = [regex]::Match($ReadableCustomUi, '(?ms)^local\s+function\s+rebuild_container\s*\(.*?^end\s*$').Value
foreach ($Marker in @('container:Reset()','for _, section in ipairs(sections) do','container:AddItem(nil, section)','container:Scroll_Reinit()')) {
    Assert-True ($RebuildContainerBlock -match [regex]::Escape($Marker)) `
        "Two-panel Custom native rebuild must preserve presenter order: $Marker"
}
Assert-True ($RebuildContainerBlock -notmatch 'container:Reinit\(') `
    'Two-panel Custom native rebuild must not re-sort presenter pages by GAMMA item size.'
$HoverHelper = [regex]::Match($ReadableCustomUi, '(?ms)^function\s+update_item_hover\s*\(.*?^end\s*$').Value
Assert-True ($HoverHelper -notmatch 'type\s*\(\s*(?:catalog_container|selected_container|inventory_container|loadout_container|item_info)\s*\)\s*~=\s*"table"') `
    'Readable Custom hover must use live capabilities instead of rejecting X-Ray userdata.'
foreach ($Marker in @('function initialize_faction','function status_presentation',
    'self.ports.initial_faction_index','infrastructure_error_code','last_reported_status_code')) {
    Assert-True ($ReadableCustomUi -match [regex]::Escape($Marker)) "Readable Custom UI is missing $Marker"
}
foreach ($Marker in @('function apply_faction_selection','function handle_escape','function readiness_presentation',
    'gamma_arena_ui_faction_picker.new','function UICustom:OpenFactionPicker','function UICustom:ApplyFaction',
    'self.faction_picker:open(view.faction_ids, view.faction)','self.faction_button:TextControl():SetText(faction_text(view.faction))',
    'texture_id(view.faction)','handle_escape(self.faction_picker')) {
    Assert-True ($ReadableCustomUi -match [regex]::Escape($Marker)) "Custom UX integration is missing $Marker"
}
Assert-True ($ReadableCustomUi -notmatch 'faction_combo') `
    'Custom UX must replace the anonymous faction combo with the emblem picker trigger.'
$CustomKeyboardBlock = [regex]::Match($ReadableCustomUi, '(?ms)^function\s+UICustom:OnKeyboard\(.*?^end\s*$').Value
Assert-True ($CustomKeyboardBlock -match 'handle_escape\(self\.faction_picker' -and
    $CustomKeyboardBlock -match 'return\s+true') `
    'Custom UX keyboard handling must consume modal Escape with an engine-compatible boolean.'
Assert-True ($CustomKeyboardBlock -notmatch 'return\s+handle_escape') `
    'Custom UX OnKeyboard must not return a structured Result table across the engine boolean boundary.'
foreach ($Marker in @('function format_price_text','function arena_price_text','function update_item_hover',
    'utils_ui.UIInfoItem(self)','function UICustom:Update()','pcall(catalog_update, catalog_container, item_info)',
    'pcall(selected_update, selected_container, item_info)')) {
    Assert-True ($ReadableCustomUi -match [regex]::Escape($Marker)) "Readable Custom hover is missing $Marker"
}
Assert-True ($ReadableCustomUi -match 'Add_CustomText\(\s*format_price_text\(') `
    'Readable Custom cell price must be formatted with an explicit AP unit'
foreach ($Locale in @('eng','rus')) {
    $ReadableTextPath = Join-Path $RepoRoot "src\gamedata\configs\text\$Locale\st_gamma_arena_custom_readability.xml"
    Assert-True (Test-Path -LiteralPath $ReadableTextPath) "Readable Custom $Locale localization companion is missing"
    $Text = if (Test-Path -LiteralPath $ReadableTextPath) { Get-Content -LiteralPath $ReadableTextPath -Raw } else { '' }
    foreach ($Id in @('st_gamma_arena_custom_incomplete_faction','st_gamma_arena_custom_incomplete_items',
        'st_gamma_arena_custom_incomplete_outfit',
        'st_gamma_arena_custom_incomplete_knife','st_gamma_arena_custom_incomplete_weapon',
        'st_gamma_arena_custom_incomplete_ammo','st_gamma_arena_custom_incomplete_healing',
        'st_gamma_arena_custom_error_budget','st_gamma_arena_custom_error_weight',
        'st_gamma_arena_custom_error_compatibility','st_gamma_arena_custom_error_limit',
        'st_gamma_arena_custom_error_action','st_gamma_arena_custom_error_setup',
        'st_gamma_arena_custom_arena_price','st_gamma_arena_custom_inventory','st_gamma_arena_custom_loadout',
        'st_gamma_arena_custom_search','st_gamma_arena_custom_filter_all','st_gamma_arena_custom_filter_weapon',
        'st_gamma_arena_custom_filter_ammo','st_gamma_arena_custom_filter_armor',
        'st_gamma_arena_custom_filter_medicine','st_gamma_arena_custom_filter_other',
        'st_gamma_arena_custom_sort_price_asc','st_gamma_arena_custom_sort_price_desc',
        'st_gamma_arena_custom_sort_name_asc','st_gamma_arena_custom_sort_name_desc',
        'st_gamma_arena_custom_points_available','st_gamma_arena_custom_points_used',
        'st_gamma_arena_custom_readiness_outfit','st_gamma_arena_custom_readiness_knife',
        'st_gamma_arena_custom_readiness_weapon','st_gamma_arena_custom_readiness_ammo',
        'st_gamma_arena_custom_readiness_healing','st_gamma_arena_custom_error_points_deficit',
        'st_gamma_arena_custom_opponents_group','st_gamma_arena_custom_conditions_group',
        'st_gamma_arena_custom_fight_seed','st_gamma_arena_custom_player_device',
        'st_gamma_arena_custom_search_label',
        'st_gamma_arena_custom_seed_helper','st_gamma_arena_custom_device_helper',
        'st_gamma_arena_custom_roster_helper','st_gamma_arena_custom_required_to_start',
        'st_gamma_arena_custom_ready_to_start','st_gamma_arena_custom_faction_picker_title',
        'st_gamma_arena_custom_faction_picker_hint','st_gamma_arena_custom_cancel',
        'st_gamma_arena_custom_random_mode')) {
        Assert-True ($Text -match ('id="' + [regex]::Escape($Id) + '"')) "Readable Custom $Locale localization is missing $Id"
    }
}
$Task9ItemCatalog = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_item_catalog.script') -Raw
foreach ($Marker in @('catalog.base_budget = reconciled_ranks.value.base_budget','catalog.max_entries = reconciled_ranks.value.max_entries')) {
    Assert-True ($Task9ItemCatalog -match [regex]::Escape($Marker)) "Task 9 composed catalog must propagate reconciled custom rule field: $Marker"
}

$Task3DeviceConfig = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_config.script') -Raw
$Task3DeviceCodec = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_codec.script') -Raw
$Task3DeviceModel = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_setup_model.script') -Raw
foreach ($Marker in @('actor_device','GA_CUSTOM_DEVICE_UNKNOWN','GA_CUSTOM_DEVICE_IN_ITEMS')) {
    Assert-True ($Task3DeviceConfig -match [regex]::Escape($Marker)) "Task 3 Custom config is missing $Marker"
}
Assert-True ($Task3DeviceCodec -match 'prefix\s*\.\.\s*"actor_device"') 'Task 3 codec must own one bounded actor_device key.'
foreach ($Marker in @('function Model:set_device','device_options','disabled_reason','affordable')) {
    Assert-True ($Task3DeviceModel -match [regex]::Escape($Marker)) "Task 3 Custom model is missing $Marker"
}
Assert-True ($Task3DeviceModel -notmatch 'CATEGORY_IDS\s*=\s*\{[^\r\n]*device') 'Task 3 devices must stay outside ordinary item categories.'
$Task3DeviceUi = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_custom.script') -Raw
foreach ($Marker in @('device_combo','OnDevice','st_gamma_arena_custom_device_none','option.disabled','device_option_text')) {
    Assert-True ($Task3DeviceUi -match [regex]::Escape($Marker)) "Task 3 Custom UI is missing $Marker"
}
foreach ($Marker in @('function resolve_device_option','function apply_device_selection','self.device_combo:AddItem(option.display_text','apply_device_selection(self.model, view.device_options')) {
    Assert-True ($Task3DeviceUi -match [regex]::Escape($Marker)) "Task 3 Custom UI canonical device path is missing $Marker"
}
[xml]$Task3DeviceXml = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\configs\ui\gamma_arena_custom.xml') -Raw
Assert-True ($null -ne $Task3DeviceXml.SelectSingleNode("//*[local-name()='device']")) 'Task 3 UI XML must expose the dedicated device selector.'
Assert-True ($null -eq $Task3DeviceXml.SelectSingleNode("//*[local-name()='category_device']")) 'Task 3 UI XML must not add an ordinary device category.'
foreach ($Locale in @('eng','rus')) {
    $Path = Join-Path $RepoRoot "src\gamedata\configs\text\$Locale\st_gamma_arena_custom_device.xml"
    Assert-True (Test-Path -LiteralPath $Path) "Task 3 $Locale device localization companion is missing."
    if (Test-Path -LiteralPath $Path) {
        [xml]$Task3LocaleDocument = Get-Content -LiteralPath $Path -Raw
        foreach ($Id in @('st_gamma_arena_custom_device','st_gamma_arena_custom_device_none','st_gamma_arena_custom_device_headlamp','st_gamma_arena_custom_device_nv_gen1','st_gamma_arena_custom_device_nv_gen2','st_gamma_arena_custom_device_nv_gen3')) {
            Assert-True ($null -ne $Task3LocaleDocument.SelectSingleNode("//string[@id='$Id']/text")) "Task 3 $Locale localization is missing $Id"
        }
    }
}
$Task3DeviceTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_custom_config.script') -Raw
foreach ($Name in @('custom_config_devices_are_optional_budgeted_and_bounded','custom_config_device_counts_and_totals_are_bounded','custom_setup_model_device_selection_is_dedicated','custom_setup_model_rejects_device_mutations_atomically','custom_codec_persists_optional_device_with_one_key')) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($Task3DeviceTests, $Registration)).Count -eq 1) "Task 3 device case must be registered exactly: $Name"
}
foreach ($Marker in @('device is distinct entry 65','device is physical entity 257','GA_CUSTOM_OVERSPEND','GA_CUSTOM_OVERWEIGHT','preserves snapshot','208')) {
    Assert-True ($Task3DeviceTests -match [regex]::Escape($Marker)) "Task 3 device tests are missing $Marker"
}
$Task3DeviceRuntime = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
$Task3DeviceRuntimeName = 'runtime_custom_ui_device_projection_round_trips_all_choices'
$Task3DeviceRuntimeRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($Task3DeviceRuntimeName) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Task3DeviceRuntimeName) + '\s*\}'
Assert-True (([regex]::Matches($Task3DeviceRuntime, $Task3DeviceRuntimeRegistration)).Count -eq 1) "Task 3 runtime device projection case must be registered exactly: $Task3DeviceRuntimeName"
foreach ($Marker in @('emitted request preserves dedicated device','Task 3 does not materialize actor_device into FightSpec items','Task 3 emits no separate FightSpec device field')) {
    Assert-True ($Task3DeviceRuntime -match [regex]::Escape($Marker)) "Task 3 runtime boundary test is missing: $Marker"
}

$Task5RequiredArtifacts = @(
    'src\gamedata\scripts\gamma_arena_random_generator.script',
    'src\gamedata\scripts\gamma_arena_custom_generator.script',
    'src\gamedata\scripts\gamma_arena_fight_builder.script',
    'src\gamedata\scripts\gamma_arena_fight_spec.script',
    'dev\gamedata\scripts\gamma_arena_test_generator.script',
    'dev\gamedata\scripts\gamma_arena_test_custom_generator.script',
    'dev\gamedata\scripts\gamma_arena_test_fight_spec.script',
    'tests\reference\New-GammaArenaRandomSemanticSnapshot.ps1',
    'tests\reference\New-GammaArenaGoldenFights.ps1',
    'tests\fixtures\golden-random-selections-v9.txt',
    'tests\fixtures\golden-fights-v9.txt'
)
$Task5ChecksRequired = (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) -or
    (Test-Path -LiteralPath (Join-Path $RepoRoot 'tests\reference\New-GammaArenaRandomSemanticSnapshot.ps1'))
if ($Task5ChecksRequired) {
$Task5ArtifactsComplete = $true
foreach ($Path in $Task5RequiredArtifacts) {
    $Exists = Test-Path -LiteralPath (Join-Path $RepoRoot $Path)
    Assert-True $Exists "Task 5 required artifact is missing: $Path"
    if (-not $Exists) { $Task5ArtifactsComplete = $false }
}
if ($Task5ArtifactsComplete) {
$Task5RandomGenerator = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_random_generator.script') -Raw
$Task5CustomGenerator = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_generator.script') -Raw
$Task5RandomTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_generator.script') -Raw
$Task5CustomTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_custom_generator.script') -Raw
Assert-True ($Task5RandomGenerator -match 'gamma_arena_device_generator\.generate') 'Task 5 Random generator must select one isolated actor device.'
$Task5DeviceSelector = 'gamma_arena_device_generator.generate'
$Task5DeviceSelectIndex = $Task5RandomGenerator.IndexOf($Task5DeviceSelector)
$Task5OpponentBudgetIndex = $Task5RandomGenerator.LastIndexOf('local gear = loadout(')
$Task5EnemyMedicalBudgetIndex = $Task5RandomGenerator.IndexOf('gamma_arena_medical_generator.allocate_enemies')
$Task5DeviceAppendIndex = $Task5RandomGenerator.IndexOf('append_item(draft.actor.loadout.items, actor_device.value.section, 1, "device")')
$Task5DraftReturnIndex = $Task5RandomGenerator.LastIndexOf('return gamma_arena_result.ok(draft)')
$Task5DeviceOrderValid = (([regex]::Matches($Task5RandomGenerator, [regex]::Escape($Task5DeviceSelector))).Count -eq 1 -and
    $Task5DeviceSelectIndex -gt $Task5OpponentBudgetIndex -and $Task5DeviceSelectIndex -gt $Task5EnemyMedicalBudgetIndex -and
    $Task5DeviceAppendIndex -gt $Task5DeviceSelectIndex -and $Task5DraftReturnIndex -gt $Task5DeviceAppendIndex)
Assert-True $Task5DeviceOrderValid 'Task 5 Random device selector must run exactly once after all actor/opponent AP decisions, then append before return.'
Assert-True ($Task5RandomGenerator -match 'kind\s*=\s*"items"' -and $Task5RandomGenerator -notmatch 'kind\s*=\s*"legacy"') 'Task 5 Random generator must emit only universal item drafts.'
Assert-True ($Task5CustomGenerator -match 'config\.actor_device' -and $Task5CustomGenerator -match 'equipped_slot\s*=\s*"device"') 'Task 5 Custom generator must append the exact selected actor_device once.'
foreach ($Marker in @('universal_v9_random_device_generation','builder and validator do not rerun Random device selection','Random emits exactly one actor device','changed Random seeds vary the selected device')) {
    Assert-True ($Task5RandomTests -match [regex]::Escape($Marker)) "Task 5 Random Dev assertion is missing: $Marker"
}
foreach ($Marker in @('custom_actor_device_is_optional_exact_and_prebudgeted','Custom emits zero or one exact selected device','Custom device AP was charged in config','Custom selection survives build and validation without reroll')) {
    Assert-True ($Task5CustomTests -match [regex]::Escape($Marker)) "Task 5 Custom Dev assertion is missing: $Marker"
}
Assert-True ($Task5CustomTests -notmatch 'CUSTOM_GOLDEN_V8') 'Task 5 must remove the embedded CUSTOM_GOLDEN_V8 bridge.'
$Task5RandomReference = Get-Content -LiteralPath (Join-Path $RepoRoot 'tests\reference\New-GammaArenaRandomSemanticSnapshot.ps1') -Raw
Assert-True ($Task5RandomReference -match 'golden-random-selections-v9\.txt' -and $Task5RandomReference -notmatch 'golden-random-selections-v8\.txt') 'Task 5 Random oracle must target only the v9 semantic snapshot.'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'tests\fixtures\golden-random-selections-v9.txt')) 'Task 5 v9 Random semantic snapshot is missing.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'tests\fixtures\golden-random-selections-v8.txt'))) 'Task 5 stale v8 Random semantic snapshot must be deleted.'
}
}

$Task10ArtifactsPresent = Test-Path -LiteralPath (Join-Path $RepoRoot 'tests\reference\New-GammaArenaGoldenFights.ps1')
if ($Task10ArtifactsPresent) {
$Task10CustomContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_custom_generator.script'; Namespace = 'gamma_arena_custom_generator'; Required = @('(?m)^function\s+build_draft\s*\(\s*session\s*,\s*fight_index\s*,\s*catalog\s*,\s*layout\s*\)', '"custom-v1"', 'catalog_fingerprint', 'validate_exact_weapon_pool', 'gamma_arena_custom_config.validate_weapon_pool', 'validate_layout_preflight', 'catalog_item_matches', 'GA_CUSTOM_WEAPON_POOL_INVALID', 'GA_CUSTOM_LAYOUT_INVALID', 'enemy_grenade_presence', 'enemy_grenade_section', 'kind\s*=\s*"items"', 'GA_CUSTOM_GENERATION_FAILED') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_custom_generator.script'; Namespace = 'gamma_arena_test_custom_generator'; Required = @('(?m)^function\s+run\s*\(', 'custom_generation_is_deterministic_and_exact', 'custom_generation_skips_enemy_equipment_outside_universal_catalog', 'custom_generation_fails_without_physical_enemy_equipment', 'merc_ace_outfit', 'GA_CUSTOM_EQUIPMENT_UNAVAILABLE', 'custom_fight_index_rerolls_only_enemy_random_fields', 'custom_builder_erases_recipe_provenance_and_accepts_carried_weapons', 'custom_generation_fails_closed_for_capacity_and_corruption', 'custom_generation_preflights_every_pool_member', 'custom_generation_preflights_every_layout_entry', 'custom_generation_rejects_noncanonical_profile_alias', 'ordered_items_signature', 'enemy weapon comes from exact faction-rank pool', 'expert', 'master', 'legend', 'arena_enemy') },
    [PSCustomObject]@{ Path = 'tests\fixtures\custom-catalog-v10.json'; Required = @('"schema_version"\s*:\s*10', '"catalog_fingerprint"\s*:\s*"ga-catalog-v10-', '"rank_ids"', '"equipment_pools"', '"actor_cases"') }
)
foreach ($Contract in $Task10CustomContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 10 custom generator contract is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        if ($Contract.Namespace) {
            $NamespacePattern = [regex]::Escape($Contract.Namespace)
            Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 10 script must not create a self-named namespace table: $($Contract.Path)"
        }
        foreach ($Pattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $Pattern) "Task 10 marker is missing from $($Contract.Path): $Pattern"
        }
    }
}
$Task10Builder = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_builder.script') -Raw
foreach ($Marker in @('gamma_arena_custom_generator.build_draft','generation_recipe','gamma_arena_fight_validator_v9.validate')) {
    Assert-True ($Task10Builder -match [regex]::Escape($Marker)) "Task 10 builder dispatch is missing: $Marker"
}
$Task10Medical = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_medical_generator.script') -Raw
Assert-True ($Task10Medical -match '(?m)^function\s+allocate_custom_enemies\s*\(') 'Task 10 custom enemy medicine allocator is missing.'
$Task10Domain = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_domain.script') -Raw
Assert-True ($Task10Domain -match 'gamma_arena_test_custom_generator\.run\s*\(\s*run_case_fn\s*\)') 'Task 10 custom generator tests must run from the Dev domain suite.'
$Task10Oracle = Get-Content -LiteralPath (Join-Path $RepoRoot 'tests\reference\New-GammaArenaGoldenFights.ps1') -Raw
foreach ($Marker in @('golden-fights-v9.txt','Get-GaLayoutHash',"ConvertTo-GaScalar 'schema_version' 9",'ga9-')) {
    Assert-True ($Task10Oracle -match [regex]::Escape($Marker)) "Task 4 independent v9 oracle is missing: $Marker"
}
Assert-True ($Task10Oracle -notmatch 'gamma_arena_(?:random_|custom_)?generator\.script') 'Task 4 reference oracle must not read Lua generator source.'
$Task10CustomGenerator = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_generator.script') -Raw
Assert-True ($Task10CustomGenerator -notmatch 'slot_stream\s*\([^\)]*,\s*"profile"\s*\)') 'Task 10 fixed exact profile alias must not consume a meaningless RNG stream.'
Assert-True ($Task10CustomGenerator -match 'profile\.alias\s*~=\s*"gamma_arena_"\s*\.\.\s*faction\.community\s*\.\.\s*"_"\s*\.\.\s*roster_entry\.rank') 'Task 10 generator must reject a noncanonical fixed faction-rank alias before RNG.'
$Task10GoldenRows = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'tests\fixtures\golden-fights-v9.txt') | Where-Object { $_ -and -not $_.StartsWith('#') })
$Task10RandomRows = @($Task10GoldenRows | Where-Object { $_ -match '^seed=' })
$Task10CustomRows = @($Task10GoldenRows | Where-Object { $_ -match '^custom=' })
Assert-True ($Task10RandomRows.Count -eq 4 -and $Task10CustomRows.Count -eq 6 -and $Task10GoldenRows.Count -eq 10) 'Task 5 sole v9 fixture must contain four Random and six Custom device-aware rows.'
$Task10DevCustom = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_custom_generator.script') -Raw
foreach ($Marker in @('duplicate exact-pool member fails before RNG','duplicate tactical route fails before RNG','duplicate spawn-slot ID fails before RNG','gamma_arena_rng.derive_seed = function','derive calls before failure')) {
    Assert-True ($Task10DevCustom -match [regex]::Escape($Marker)) "Task 12 fail-closed pre-RNG regression is missing: $Marker"
}
foreach ($Forbidden in @('mode_id=','difficulty_id=','budget=','price=','custom_config=','generation_recipe=')) {
    Assert-True (@($Task10GoldenRows | Where-Object { $_.Substring($_.IndexOf('stable_encode=') + 14).Contains($Forbidden) }).Count -eq 0) "Task 4 v9 golden encodings must erase $Forbidden"
}
}

$Task11Runtime = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Name in @(
    'runtime_custom_session_creation_copies_validated_recipe',
    'runtime_custom_session_snapshot_preserves_dense_arrays_for_composed_actor_ownership',
    'runtime_custom_stale_catalog_rejects_before_actor_mutation',
    'runtime_custom_launch_uses_one_catalog_layout_snapshot_for_real_store',
    'runtime_custom_rejects_unbound_resolved_layout_before_store_ownership',
    'runtime_composed_actor_sets_and_verifies_real_weapon_ammo_type',
    'runtime_composed_actor_tag_failures_rollback_provisional_items_exactly',
    'runtime_composed_default_actor_materializes_universal_inventory_and_restores_template',
    'runtime_custom_defeat_opens_fresh_default_setup_without_loadout'
)) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($Task11Runtime, $Registration)).Count -eq 1) "Task 11 runtime case must be registered exactly: $Name"
}
$Task11Session = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script') -Raw
Assert-True ($Task11Session -match 'arena_session_keys\s*=\s*\{[\s\S]{0,700}generation_recipe\s*=\s*true[\s\S]{0,400}catalog_fingerprint\s*=\s*true[\s\S]{0,400}custom_config\s*=\s*true') 'Task 11 ArenaSession must own recipe, catalog fingerprint, and custom config provenance.'
Assert-True ($Task11Session -match 'session\.generator_version\s*~=\s*11' -and $Task11Session -match 'session\.catalog_revision\s*~=\s*11') 'Task 11 ArenaSession must bind current catalog/generator identity 11/11.'
Assert-True ($Task11Session -match 'gamma_arena_custom_config\.validate\s*\(\s*session\.custom_config') 'Task 11 ArenaSession must independently validate and copy custom config.'
$Task11Orchestrator = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script') -Raw
$Task11Bootstrap = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
Assert-True ($Task11Orchestrator -match 'function\s+Orchestrator:create_session\s*\(\s*request\s*,\s*catalog\s*,\s*layout\s*\)') 'Task 11 session creation must consume the active catalog and layout.'
Assert-True ($Task11Orchestrator -match 'local function\s+custom_validation_context\s*\(') `
    'Custom activation must separate logical catalog layout validation from the physical resolved layout.'
Assert-True ($Task11Orchestrator -match 'custom_validation_context\s*\(\s*catalog\s*,\s*layout\s*\)[\s\S]{0,500}if\s+not\s+context\.ok\s+then\s+return\s+context\s+end[\s\S]{0,900}validate_arena_session') `
    'Custom session creation must fail closed before validating against the catalog logical layout.'
Assert-True ($Task11Orchestrator -match 'GA_ACTOR_LAYOUT_INVALID[\s\S]{0,700}layouts\s*\[\s*resolved_layout\.id\s*\]') `
    'Custom validation context must require an exact resolved-to-logical layout identity.'
Assert-True ($Task11Orchestrator -match 'catalog_fingerprint\s*=\s*catalog\.fingerprint') 'Task 11 session creation must bind the loaded catalog fingerprint.'
Assert-True ($Task11Orchestrator -match 'local\s+layout\s*=\s*self:layout_snapshot\(self\.catalog_snapshot\)') 'Task 11 continuation actor reset must resolve layout from the same validated catalog snapshot as its FightSpec.'
Assert-True (([regex]::Matches($Task11Orchestrator, 'self:layout_snapshot\(self\.catalog_snapshot\)')).Count -ge 2) 'Task 11 initial normalization and continuation reset must both retain the FightSpec catalog snapshot.'
$Task11IdentityIndex = $Task11Orchestrator.IndexOf('validate_session_catalog_identity')
$Task11GenerateIndex = $Task11Orchestrator.IndexOf('self.deps.generator')
Assert-True ($Task11IdentityIndex -ge 0 -and $Task11GenerateIndex -gt $Task11IdentityIndex) 'Task 11 catalog identity validation must precede fight generation and actor mutation.'
Assert-True ($Task11Orchestrator -match 'local function\s+plain_table_shape' -and $Task11Orchestrator -match 'dense positive-integer') 'Task 11 ArenaSession copy must distinguish dense arrays from string-key records.'
foreach ($Marker in @('resolved layout intentionally has no virtual_capacity',
    'real Store validates Custom config against the catalog logical layout',
    'real Store never validates Custom config against the physical resolved layout',
    'fight generator receives the physical resolved layout',
    'fight validator receives the physical resolved layout',
    'layout identity rejects before launch consumption')) {
    Assert-True ($Task11Runtime -match [regex]::Escape($Marker)) `
        "Custom logical/resolved layout regression is missing: $Marker"
}
$Task10CustomGeneratorTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_custom_generator.script') -Raw
$CustomPhysicalCatalogCase = 'custom_generation_skips_enemy_equipment_outside_universal_catalog'
$CustomPhysicalCatalogRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($CustomPhysicalCatalogCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($CustomPhysicalCatalogCase) + '\s*\}'
Assert-True (([regex]::Matches($Task10CustomGeneratorTests, $CustomPhysicalCatalogRegistration)).Count -eq 1) `
    "Regression case must be registered exactly: $CustomPhysicalCatalogCase -> $CustomPhysicalCatalogCase."
$CustomPhysicalFailureCase = 'custom_generation_fails_without_physical_enemy_equipment'
$CustomPhysicalFailureRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($CustomPhysicalFailureCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($CustomPhysicalFailureCase) + '\s*\}'
Assert-True (([regex]::Matches($Task10CustomGeneratorTests, $CustomPhysicalFailureRegistration)).Count -eq 1) `
    "Regression case must be registered exactly: $CustomPhysicalFailureCase -> $CustomPhysicalFailureCase."
Assert-True ($Task11Bootstrap -match 'function\s+new_actor_item_port\s*\(' -and $Task11Bootstrap -match 'gamma_arena_item_materializer\.new\s*\(') 'Task 11 production actor path must construct the universal item materializer.'
Assert-True ($Task11Bootstrap -notmatch 'local value = \{ consumables = \{\}, grenades = \{\} \}') 'Task 11 production actor path must not flatten universal items into a legacy single-weapon loadout.'
Assert-True ($Task11Bootstrap -match 'weapon:set_ammo_type\s*\(' -and $Task11Bootstrap -match 'weapon:get_ammo_type\s*\(') 'Task 11 production actor path must set and verify the real engine ammunition type.'
Assert-True ($Task11Bootstrap -notmatch 'magazine_ammo\s*\[\s*id\s*\]\s*=\s*ammo_section') 'Task 11 production actor path must not verify ammunition against a locally asserted expected value.'
$Task11Compat = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script') -Raw
Assert-True ($Task11Compat.Contains('game_object.set_ammo_type') -and $Task11Compat.Contains('game_object.get_ammo_type')) 'Task 11 compatibility preflight must require real weapon ammunition type APIs.'
Assert-True ($Task11Bootstrap -match 'provisional_by_entity' -and $Task11Bootstrap -match 'exact_provisional_record') 'Task 11 production actor rollback must own exact transaction-local provisional records.'
$Task11ActivateStart = $Task11Orchestrator.IndexOf('function Orchestrator:activate_once')
$Task11ActivateEnd = if ($Task11ActivateStart -ge 0) { $Task11Orchestrator.IndexOf('function Orchestrator:layout_snapshot', $Task11ActivateStart) } else { -1 }
Assert-True ($Task11ActivateStart -ge 0 -and $Task11ActivateEnd -gt $Task11ActivateStart) 'Task 11 activation boundary must remain structurally testable.'
if ($Task11ActivateStart -ge 0 -and $Task11ActivateEnd -gt $Task11ActivateStart) {
    $Task11Activate = $Task11Orchestrator.Substring($Task11ActivateStart, $Task11ActivateEnd - $Task11ActivateStart)
    Assert-True ($Task11Activate -match 'merge_launch_options\s*\(\s*self\.deps\.launch_options\s*,\s*activation_catalog\s*,\s*activation_layout\s*\)' -and $Task11Activate -match 'activation_launch_options\s*=\s*launch_options\.value') 'Task 11 activation must create one non-mutating launch-options snapshot.'
    Assert-True (([regex]::Matches($Task11Activate, 'self\.deps\.config\s*,\s*activation_launch_options')).Count -eq 2) 'Task 11 Store ownership validation and consumption must share the exact activation options object.'
}
$Task11DefeatStart = $Task11Runtime.IndexOf('local function runtime_custom_defeat_opens_fresh_default_setup_without_loadout')
$Task11DefeatEnd = if ($Task11DefeatStart -ge 0) { $Task11Runtime.IndexOf('local function task11_item_signature', $Task11DefeatStart) } else { -1 }
Assert-True ($Task11DefeatStart -ge 0 -and $Task11DefeatEnd -gt $Task11DefeatStart) 'Task 11 custom defeat regression must remain structurally testable.'
if ($Task11DefeatStart -ge 0 -and $Task11DefeatEnd -gt $Task11DefeatStart) {
    $Task11Defeat = $Task11Runtime.Substring($Task11DefeatStart, $Task11DefeatEnd - $Task11DefeatStart)
    Assert-True ($Task11Defeat -match 'gamma_arena_session_store\.new_store\s*\(' -and $Task11Defeat -match ':arm_defeat\s*\(' -and $Task11Defeat -match ':confirm_defeat\s*\(' -and $Task11Defeat -match ':peek_defeat\s*\(' -and $Task11Defeat -match ':consume_defeat\s*\(') 'Task 11 custom defeat regression must exercise the real Store round trip.'
    Assert-True ($Task11Defeat -match 'gad1:1000:custom' -and $Task11Defeat -notmatch 'gad2:') 'Task 11 custom defeat regression must use the production schema/token grammar.'
}
$Task11MainMenu = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_main_menu.script') -Raw
Assert-True ($Task11Session -match 'defeat_generation_recipe') 'Task 11 defeat handoff must retain recipe provenance.'
Assert-True ($Task11Session -notmatch 'defeat_custom_(?:config|item|roster)') 'Task 11 defeat handoff must never persist the defeated custom loadout.'
Assert-True ($Task11MainMenu -match 'function\s+open_default_custom_setup\s*\(' -and $Task11MainMenu -match 'generation_recipe\s*==\s*"custom"') 'Task 11 custom defeat must open a fresh default custom setup.'
$Task11Migrations = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_migrations.script') -Raw
Assert-True ($Task11Migrations -match [regex]::Escape('defeat_generation_recipe')) 'Task 11 migration cleanup must own the defeat recipe key.'
$Task11Bootstrap = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
Assert-True ($Task11Bootstrap -match 'local\s+layout_port\s*=\s*overrides\.layout\s+or\s+function\s*\(\s*layout_id\s*,\s*catalog_snapshot\s*\)' -and $Task11Bootstrap -match 'catalog_snapshot\s+and\s+gamma_arena_result\.ok\(catalog_snapshot\)') 'Task 11 bootstrap layout resolution must reuse the supplied universal catalog snapshot.'
Assert-True ($Task11Bootstrap -match 'local\s+preflight_port\s*=\s*overrides\.preflight\s+or\s+function\s*\(\s*catalog_snapshot\s*\)' -and $Task11Bootstrap -match 'runtime_probes\(catalog_snapshot\)') 'Task 11 bootstrap compatibility preflight must reuse the supplied universal catalog snapshot.'
Assert-True ($Task11Bootstrap -match 'gamma_arena_fight_builder\.generate\(session,\s*fight_index,\s*catalog_snapshot,\s*resolved_layout\)') 'Task 11 bootstrap must dispatch both recipes through the universal fight builder.'
$Task11RuntimeTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Marker in @(
    'runtime_custom_first_fight_preserves_shared_roster_actor_hud_and_audio',
    'runtime_custom_victory_rerolls_enemy_only_with_immutable_template',
    'runtime_custom_integrity_retry_is_object_identical_and_restart_preserves_policy',
    'runtime_custom_recipe_failures_are_exact_before_world_mutation',
    'runtime_random_recipe_session_remains_difficulty_only'
)) {
    Assert-True ($Task11RuntimeTests -match [regex]::Escape($Marker)) "Task 11 runtime lifecycle tests must cover $Marker"
}
$Task11CustomUi = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_custom.script') -Raw
Assert-True ($Task11CustomUi -match 'DIK_keys\.DIK_ESCAPE[\s\S]{0,300}handle_escape\(self\.faction_picker[\s\S]{0,160}self:OnBack\(\)') 'Task 11 custom setup Escape must cancel the faction modal before using the non-launching back path.'

$Task12BuildPath = Join-Path $RepoRoot 'tools\Build-GammaArena.ps1'
if (Test-Path -LiteralPath $Task12BuildPath) {
    $Task12Build = Get-Content -LiteralPath $Task12BuildPath -Raw
    foreach ($Path in @('tests\fixtures\golden-random-selections-v9.txt','tests\fixtures\custom-catalog-v10.json')) {
        Assert-True ($Task12Build -match [regex]::Escape($Path)) "Task 12 Dev package inventory is missing: $Path"
    }
}

foreach ($Path in $Task7CurrentArtifacts) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $Path)) "Task 4 current-only v9 artifact is missing: $Path"
}
foreach ($Version in 1..8) {
    foreach ($Path in @("schemas\fight-spec-v$Version.md", "tests\fixtures\golden-fights-v$Version.txt")) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Path))) "Task 4 must delete retired FightSpec artifact: $Path"
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "src\gamedata\scripts\gamma_arena_fight_validator_v$Version.script"))) "Task 4 must delete retired FightSpec validator v$Version."
}
if (Test-Path -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_builder.script')) {
    $Task7Builder = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_builder.script') -Raw
    foreach ($Marker in @('gamma_arena_random_generator.build_draft', 'gamma_arena_fight_spec.canonicalize', 'generator_version = catalog.generator_version', 'gamma_arena_fight_validator_v9.validate', 'catalog_schema_version = catalog.schema_version', 'catalog_revision = catalog.revision', 'layout_hash = gamma_arena_fight_spec.layout_hash(layout)')) {
        Assert-True ($Task7Builder -match [regex]::Escape($Marker)) "Task 4 v9 builder is missing: $Marker"
    }
    $Task7BuilderIdentityIndex = $Task7Builder.IndexOf('validate_catalog_identity')
    $Task7BuilderDraftIndex = $Task7Builder.IndexOf('gamma_arena_random_generator.build_draft')
    Assert-True ($Task7BuilderIdentityIndex -ge 0 -and $Task7BuilderIdentityIndex -lt $Task7BuilderDraftIndex) 'Task 7 builder must reject the wrong catalog identity before random draft generation.'
}
$Task7CatalogMetadata = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx') -Raw
Assert-True ($Task7CatalogMetadata -match '(?ms)\[meta\].*?schema_version\s*=\s*10\s*.*?revision\s*=\s*11\s*.*?generator_version\s*=\s*11') 'Task 7 catalog identity must be 10/11/11.'
$Task7OrchestratorIdentity = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script') -Raw
$Task7SessionStoreIdentity = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script') -Raw
$Task7RuntimeSessionFixtures = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Pattern in @('catalog\.schema_version\s*~=\s*10', 'catalog\.revision\s*~=\s*11', 'catalog\.generator_version\s*~=\s*11')) {
    Assert-True ($Task7OrchestratorIdentity -match $Pattern) "Task 7 orchestrator catalog guard must enforce current identity: $Pattern"
}
foreach ($Pattern in @('session\.generator_version\s*~=\s*11', 'session\.catalog_revision\s*~=\s*11')) {
    Assert-True ($Task7SessionStoreIdentity -match $Pattern) "Task 7 ArenaSession guard must enforce current identity: $Pattern"
}
Assert-True ($Task7RuntimeSessionFixtures -match '(?ms)local function valid_session\(\).*?generator_version\s*=\s*11.*?catalog_revision\s*=\s*11.*?ga-catalog-v10-') 'Task 7 current resume fixture must bind catalog identity 10/11/11.'
foreach ($CaseName in @('runtime_custom_session_creation_copies_validated_recipe','runtime_random_recipe_session_remains_difficulty_only','resume_is_validated_but_override_is_not_applied_early')) {
    Assert-True ($Task7RuntimeSessionFixtures -match [regex]::Escape($CaseName)) "Task 7 current session behavioral fixture is missing: $CaseName"
}
$Task7SessionSchemaDoc = Get-Content -LiteralPath (Join-Path $RepoRoot 'schemas\session-v1.md') -Raw
foreach ($Marker in @('FightSpec v9','catalog schema `10`','generator_version = 11','catalog_revision = 11','ga-catalog-v10-')) {
    Assert-True ($Task7SessionSchemaDoc.Contains($Marker)) "Task 7 session schema documentation is stale: $Marker"
}
$Task7CompatibilityManifestDoc = Get-Content -LiteralPath (Join-Path $RepoRoot 'schemas\compatibility-manifest-v1.md') -Raw
foreach ($Marker in @('"0.5.1"','fight_spec_schema_version` | integer | `9`','catalog_schema_version` | integer | `10`','catalog_revision` | integer | `11`','generator_version` | integer | `11`')) {
    Assert-True ($Task7CompatibilityManifestDoc.Contains($Marker)) "Task 7 compatibility manifest documentation is stale: $Marker"
}
$Task7GeneratorTest = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_generator.script') -Raw
$Task7MasterExoRegistration = '\{\s*name\s*=\s*"master_powered_exo_rate_is_rare"\s*,\s*fn\s*=\s*master_powered_exo_rate_is_rare\s*\}'
Assert-True (([regex]::Matches($Task7GeneratorTest, $Task7MasterExoRegistration)).Count -eq 1) 'Regression case must be registered exactly: master_powered_exo_rate_is_rare -> master_powered_exo_rate_is_rare.'
$Task7FightSpecContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_spec.script') -Raw
$Task7FightValidatorContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_validator_v9.script') -Raw
$Task7FightSpecTestContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_fight_spec.script') -Raw
foreach ($Pattern in @('catalog\.schema_version\s*~=\s*10', 'catalog\.revision\s*~=\s*11', 'catalog\.generator_version\s*~=\s*11', 'ga-catalog-v10-')) {
    Assert-True ($Task7FightSpecContent -match $Pattern) "Task 4 canonicalization must enforce catalog identity: $Pattern"
}
foreach ($Marker in @('canonicalizes_v9_exact_identity_and_device_order','validator_enforces_v9_identity_versions_and_devices','validator_never_reruns_random_device_selection')) {
    Assert-True ($Task7FightSpecTestContent -match [regex]::Escape($Marker)) "Task 4 v9 executable contract test is missing: $Marker"
}
Assert-True ($Task7FightSpecContent -match 'UINT32_MAX\s*=\s*4294967295') 'FightSpec canonicalization must accept the complete uint32 session-seed domain.'
Assert-True ($Task7FightValidatorContent -match 'UINT32_MAX\s*=\s*4294967295') 'FightSpec validation must accept the complete uint32 session-seed domain.'
Assert-True ($Task7FightSpecContent -match 'session_seed\s*>\s*UINT32_MAX' -and $Task7FightSpecContent -notmatch 'session_seed\s*~=\s*gamma_arena_rng\.normalize_uint32') 'FightSpec canonicalization must validate session identity as uint32, not as internal RNG state.'
Assert-True ($Task7FightValidatorContent -match 'session_seed\s*>\s*UINT32_MAX' -and $Task7FightValidatorContent -notmatch 'session_seed\s*~=\s*gamma_arena_rng\.normalize_uint32') 'FightSpec validation must validate session identity as uint32, not as internal RNG state.'
$Uint32SeedCase = 'accepts_full_uint32_session_seed_identity'
$Uint32SeedRegistration = '\{\s*name\s*=\s*"fight_spec_accepts_full_uint32_session_seed_identity"\s*,\s*fn\s*=\s*' + [regex]::Escape($Uint32SeedCase) + '\s*\}'
Assert-True (([regex]::Matches($Task7FightSpecTestContent, $Uint32SeedRegistration)).Count -eq 1) "Regression case must be registered exactly: fight_spec_accepts_full_uint32_session_seed_identity -> $Uint32SeedCase."

$Task5UniversalRuntimeContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_item_materializer.script'; Required = @('(?m)^function\s+descriptors\s*\(\s*items\s*,\s*catalog\s*\)', '(?m)^function\s+new\s*\(', '(?m)^local function\s+preflight_items\s*\(', '(?m)^local function\s+dense_array_length\s*\(', 'CATEGORY_LTX_SLOTS', 'MAX_SAFE_INTEGER', 'max_physical_items_per_participant', 'GA_ITEM_MATERIALIZE_ARRAY_INVALID', 'GA_ITEM_MATERIALIZE_DEFINITION_INVALID', 'GA_ITEM_MATERIALIZE_LIMIT', 'GA_ITEM_MATERIALIZE_UNKNOWN', 'GA_ITEM_MATERIALIZE_ROLLBACK_FAILED', 'GA_ITEM_MATERIALIZE_BONUS_PLAN_INVALID', 'bonus_descriptors', 'initialize_created', 'bonus_kind', 'box_size', 'equipped_slot') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_actor_adapter.script'; Required = @('function\s+ActorAdapter:apply_items', 'function\s+ActorAdapter:update_items') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_entity_adapter.script'; Required = @('function\s+EntityAdapter:materialize_items', 'function\s+EntityAdapter:stage_exact_rank', 'GA_ENTITY_RANK_MISMATCH', 'set_character_rank', 'character_rank') }
)
foreach ($Contract in $Task5UniversalRuntimeContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 5 universal runtime contract is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        foreach ($Pattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $Pattern) "Task 5 universal runtime marker is missing from $($Contract.Path): $Pattern"
        }
    }
}
$Task5MaterializerContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_item_materializer.script') -Raw
$AggregateRunnerPath = Join-Path $RepoRoot 'tools\Test-GammaArena.ps1'
Assert-True (Test-Path -LiteralPath $AggregateRunnerPath -PathType Leaf) 'Aggregate runner is required.'
if (Test-Path -LiteralPath $AggregateRunnerPath -PathType Leaf) {
    $AggregateRunnerContent = Get-Content -LiteralPath $AggregateRunnerPath -Raw
    Assert-True ($AggregateRunnerContent -notmatch 'Test-ActorDeviceLoadouts\.ps1') 'Aggregate runner must not invoke the removed v8 actor-device gate.'
    Assert-True (([regex]::Matches($AggregateRunnerContent, 'Test-ActorDevices\.ps1')).Count -eq 1) 'Aggregate runner must invoke the single current actor-device gate exactly once.'
}
Assert-True ($Task5MaterializerContent -notmatch 'UINT32_MOD') 'Task 5 materializer must not narrow physical quantities or box_size to uint32.'

$Task5UniversalRuntimeTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Marker in @(
    'runtime_universal_items_materialize_exact_entities_and_slot_order',
    'runtime_universal_items_preflight_enforces_physical_item_cap',
    'runtime_universal_items_rollback_every_failure_in_reverse',
    'runtime_universal_items_preflight_rejects_malformed_nested_inputs_without_mutation',
    'runtime_universal_items_rollback_failure_aggregates_original_cause',
    'runtime_universal_items_weapon1_activation_fallback',
    'runtime_entity_exact_rank_precedes_friend_tactical_and_hostility',
    'runtime_entity_adjacent_rank_readback_blocks_hostility'
)) {
    Assert-True ($Task5UniversalRuntimeTests -match [regex]::Escape($Marker)) "Task 5 runtime tests must cover $Marker"
}
foreach ($Pattern in @(
    'successful_env\.stage_counts',
    'for\s+occurrence\s*=\s*1\s*,\s*occurrence_count',
    'fail_occurrence\s*=\s*occurrence'
)) {
    Assert-True ($Task5UniversalRuntimeTests -match $Pattern) "Task 5 runtime fault matrix must cover every dependency occurrence: $Pattern"
}
$Task5UniversalBootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
foreach ($Marker in @('function set_character_rank', 'function character_rank', 'npc:set_character_rank(value)', 'npc:character_rank()')) {
    Assert-True ($Task5UniversalBootstrapContent -match [regex]::Escape($Marker)) "Task 5 bootstrap rank port is missing: $Marker"
}

$Task4ScriptContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_config_tx.script'; Namespace = 'gamma_arena_config_tx'; Required = @('(?m)^function\s+run\s*\(', '(?m)^function\s+snapshot\s*\(', '(?m)^function\s+recover\s*\(', '(?m)^function\s+is_quarantined\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_migrations.script'; Namespace = 'gamma_arena_migrations'; Required = @('(?m)^function\s+migrate\s*\(', '(?m)^function\s+read_settings\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_session_store.script'; Namespace = 'gamma_arena_session_store'; Required = @('(?m)^function\s+new_store\s*\(', '(?m)^function\s+parse_manual_seed\s*\(', '(?m)^function\s+validate_start_request\s*\(', '(?m)^function\s+random_session_seed\s*\(', '(?m)^function\s+save_preferences\s*\(', '(?m)^function\s+issue_launch\s*\(', '(?m)^function\s+parse_launch_token\s*\(', '(?m)^function\s+consume_launch\s*\(', '(?m)^function\s+issue_resume\s*\(', '(?m)^function\s+consume_resume\s*\(', '(?m)^function\s+write_character_creation\s*\(', '(?m)^function\s+restore_character_creation\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\modxml_gamma_arena.script'; Namespace = 'modxml_gamma_arena'; Required = @('(?m)^function\s+on_xml_read\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_main_menu.script'; Namespace = 'gamma_arena_main_menu'; Required = @('(?m)^function\s+on_main_menu_init\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_ui_start.script'; Namespace = 'gamma_arena_ui_start'; Required = @('class\s+"UIStart"\s+\(CUIScriptWnd\)', '(?m)^function\s+handoff_start_game\s*\(', '(?m)^function\s+create\s*\(', '(?m)^function\s+show_fatal\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_migrations.script'; Namespace = 'gamma_arena_test_migrations'; Required = @('(?m)^function\s+run\s*\(') }
)

foreach ($Contract in $Task2ScriptContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 2 script is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        $NamespacePattern = [regex]::Escape($Contract.Namespace)
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 2 script must not create a self-named namespace table: $($Contract.Path)"
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*function\s+" + $NamespacePattern + "\.")) "Task 2 script must not use self-qualified function definitions: $($Contract.Path)"
        foreach ($RequiredPattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $RequiredPattern) "Task 2 script is missing its bare engine API: $($Contract.Path)"
        }
    }
}

foreach ($Contract in $Task3ScriptContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 3 script is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        $NamespacePattern = [regex]::Escape($Contract.Namespace)
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 3 script must not create a self-named namespace table: $($Contract.Path)"
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*function\s+" + $NamespacePattern + "\.")) "Task 3 script must not use self-qualified function definitions: $($Contract.Path)"
        foreach ($RequiredPattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $RequiredPattern) "Task 3 script is missing its bare engine API: $($Contract.Path)"
        }
    }
}

$Task4Fix1ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_validator_v9.script'
if (Test-Path -LiteralPath $Task4Fix1ValidatorPath) {
    $Task4Fix1ValidatorContent = Get-Content -LiteralPath $Task4Fix1ValidatorPath -Raw
    Assert-True ($Task4Fix1ValidatorContent -notmatch 'opponent\.slot\s*~=\s*index') 'FightSpec v9 logical opponent slots must be unique rather than equal to array indices.'
}

foreach ($Contract in $Task1RankScriptContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 1 rank script is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        $NamespacePattern = [regex]::Escape($Contract.Namespace)
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 1 rank script must not create a self-named namespace table: $($Contract.Path)"
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*function\s+" + $NamespacePattern + "\.")) "Task 1 rank script must not use self-qualified function definitions: $($Contract.Path)"
        foreach ($RequiredPattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $RequiredPattern) "Task 1 rank script is missing its contract: $($Contract.Path)"
        }
    }
}

foreach ($Contract in $Task2ItemScriptContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 2 item script is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        $NamespacePattern = [regex]::Escape($Contract.Namespace)
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 2 item script must not create a self-named namespace table: $($Contract.Path)"
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*function\s+" + $NamespacePattern + "\.")) "Task 2 item script must not use self-qualified function definitions: $($Contract.Path)"
        foreach ($RequiredPattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $RequiredPattern) "Task 2 item script is missing its contract: $($Contract.Path)"
        }
    }
}

$Task1RulesPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_custom_rules.ltx'
$Task1NpcPath = Join-Path $RepoRoot 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx'
$Task1SkipPath = Join-Path $RepoRoot 'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx'
Assert-True (Test-Path -LiteralPath $Task1RulesPath) 'Task 1 custom rank rules are missing'
if (Test-Path -LiteralPath $Task1RulesPath) {
    $Task1RulesContent = Get-Content -LiteralPath $Task1RulesPath -Raw
    foreach ($Marker in @(
        'schema_version = 1', 'revision = 1', 'base_budget = 600', 'max_entries = 64', 'max_physical_items_per_participant = 256',
        'ids = army, bandit, csky, dolg, ecolog, freedom, greh, isg, killer, monolith, renegade, stalker, zombied',
        'ids = novice, trainee, experienced, professional, veteran, expert, master, legend',
        'threat = 100', 'threat = 120', 'threat = 150', 'threat = 180',
        'threat = 220', 'threat = 270', 'threat = 330', 'threat = 600', '[price_overrides]'
    )) {
        Assert-True ($Task1RulesContent.Contains($Marker)) "Task 1 custom rank rules must declare $Marker"
    }
    Assert-True ($Task1RulesContent -match '(?ms)^\[rank_legend\]\s*\r?\n\s*threat\s*=\s*600\s*$') `
        'Custom Legend threat must be exactly 600 AP.'
    $Task1RankCatalogTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_rank_catalog.script') -Raw
    foreach ($Marker in @('1200, "one legend"', '6600, "ten legends"')) {
        Assert-True ($Task1RankCatalogTests.Contains($Marker)) `
            "Rank catalog tests must pin the raised Legend budget: $Marker"
    }
}
if (Test-Path -LiteralPath $Task1NpcPath) {
    $Task1NpcContent = Get-Content -LiteralPath $Task1NpcPath -Raw
    $Task1ProfileBases = @{ army='military'; bandit='bandit'; csky='csky'; dolg='duty'; ecolog='ecolog'; freedom='freedom'; greh='greh'; isg='isg'; killer='killer'; monolith='monolith'; renegade='renegade'; stalker='stalker'; zombied='zombied' }
    $Task1ProfileTiers = @{ novice=0; trainee=1; experienced=2; professional=2; veteran=3; expert=3; master=4; legend=4 }
    foreach ($Faction in @('army','bandit','csky','dolg','ecolog','freedom','greh','isg','killer','monolith','renegade','stalker','zombied')) {
        foreach ($Rank in @('novice','trainee','experienced','professional','veteran','expert','master','legend')) {
            $Alias = "gamma_arena_${Faction}_${Rank}"
            $Expected = "(?m)^\[" + [regex]::Escape($Alias) + "\]:sim_default_" + [regex]::Escape($Task1ProfileBases[$Faction]) + "_" + $Task1ProfileTiers[$Rank] + "\r?$"
            Assert-True ($Task1NpcContent -match $Expected) "Task 1 NPC profile must map exact alias: $Alias"
        }
    }
}
if (Test-Path -LiteralPath $Task1SkipPath) {
    $Task1SkipContent = Get-Content -LiteralPath $Task1SkipPath -Raw
    Assert-True (([regex]::Matches($Task1SkipContent, '(?m)^gamma_arena_(army|bandit|csky|dolg|ecolog|freedom|greh|isg|killer|monolith|renegade|stalker|zombied)_(novice|trainee|experienced|professional|veteran|expert|master|legend)\s*=\s*(army|bandit|csky|dolg|ecolog|freedom|greh|isg|killer|monolith|renegade|stalker|zombied)\s*$')).Count -eq 104) 'Task 1 loadout patch must add all 104 exact Arena aliases to skip_npcs'
    foreach ($Faction in @('army','bandit','csky','dolg','ecolog','freedom','greh','isg','killer','monolith','renegade','stalker','zombied')) {
        foreach ($Rank in @('novice','trainee','experienced','professional','veteran','expert','master','legend')) {
            Assert-True ($Task1SkipContent -match ("(?m)^gamma_arena_" + $Faction + "_" + $Rank + "\s*=\s*" + $Faction + "\s*$")) "Task 1 loadout patch must map the exact engine faction: gamma_arena_${Faction}_${Rank}"
        }
    }
}
$Task1DomainContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_domain.script') -Raw
Assert-True ($Task1DomainContent -match 'gamma_arena_test_rank_catalog\.run\s*\(\s*run_case_fn\s*\)') 'Task 1 domain suite must register rank catalog tests'
Assert-True ($Task1DomainContent -match 'gamma_arena_test_item_catalog\.run\s*\(\s*run_case_fn\s*\)') 'Task 2 domain suite must register universal item catalog tests'
$Task2ItemCatalogContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_item_catalog.script') -Raw
Assert-True ($Task2ItemCatalogContent -match 'local function\s+reconcile_rank_catalog\s*\(') `
    'Task 2 item catalog must reconcile exact rank pools with physical item definitions before publication.'
Assert-True ($Task2ItemCatalogContent -match 'local function\s+exact_rank_weapon_record\s*\(') `
    'Task 2 rank reconciliation must distinguish malformed legacy metadata from physical ineligibility.'
$Task1RankCatalogContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_rank_catalog.script') -Raw
$Task1RankTestContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_rank_catalog.script') -Raw
Assert-True ($Task1RankTestContent -match 'rank_catalog_accepts_scalar_spawn_rank_metadata') 'Task 1 rank tests must reproduce effective scalar spawn rank metadata.'
Assert-True ($Task1RankTestContent -match 'rank_catalog_rejects_incomplete_profile_rank_ranges') 'Task 1 rank tests must reject incomplete explicit rank ranges.'
Assert-True ($Task1RankCatalogContent -match '(?m)^local function parse_optional_profile_range\s*\(') 'Task 1 rank catalog must distinguish optional spawn rank metadata from explicit bounded ranges.'
Assert-True ($Task1RankCatalogContent -match 'has_range_separator') 'Task 1 rank catalog must preserve empty explicit CSV endpoints for validation.'
Assert-True ($Task1RankCatalogContent -match 'bounded_range_pattern') 'Task 1 rank catalog must require exactly one explicit range separator.'

foreach ($Contract in $Task4ScriptContracts) {
    $ScriptPath = Join-Path $RepoRoot $Contract.Path
    Assert-True (Test-Path -LiteralPath $ScriptPath) "Task 4 script is missing: $($Contract.Path)"
    if (Test-Path -LiteralPath $ScriptPath) {
        $ScriptContent = Get-Content -LiteralPath $ScriptPath -Raw
        $NamespacePattern = [regex]::Escape($Contract.Namespace)
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*(?:local\s+)?" + $NamespacePattern + "\s*=")) "Task 4 script must not create a self-named namespace table: $($Contract.Path)"
        Assert-True ($ScriptContent -notmatch ("(?m)^\s*function\s+" + $NamespacePattern + "\.")) "Task 4 script must not use self-qualified function definitions: $($Contract.Path)"
        foreach ($RequiredPattern in $Contract.Required) {
            Assert-True ($ScriptContent -match $RequiredPattern) "Task 4 script is missing its required API: $($Contract.Path)"
        }
    }
}

$Task4DataFiles = @(
    'src\gamedata\configs\ui\gamma_arena_start.xml',
    'src\gamedata\configs\text\rus\st_gamma_arena.xml',
    'src\gamedata\configs\text\eng\st_gamma_arena.xml',
    'tests\fixtures\settings-v0.ltx',
    'tests\fixtures\settings-v1.ltx',
    'schemas\session-v1.md'
)
foreach ($RelativePath in $Task4DataFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)) "Task 4 data contract is missing: $RelativePath"
}

$MigrationPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_migrations.script'
if (Test-Path -LiteralPath $MigrationPath) {
    $MigrationContent = Get-Content -LiteralPath $MigrationPath -Raw
    Assert-True ($MigrationContent -match ('CURRENT_ADDON_VERSION\s*=\s*"' + [regex]::Escape($AddonVersion) + '"')) 'Runtime add-on version must match VERSION.'
    Assert-True ($MigrationContent -match 'GA_SETTINGS_SCHEMA_NEWER') 'Settings migration must reject future schemas'
    Assert-True ($MigrationContent -match 'events') 'Settings reads and migrations must report events'
    Assert-True ($MigrationContent -match 'settings_schema_version') 'Settings migration must write schema v1'
    Assert-True ($MigrationContent -match 'gamma_arena_config_tx\.run') 'Settings migration must use the crash-safe config transaction adapter'
    Assert-True ($MigrationContent -match 'gamma_arena_config_tx\.is_quarantined') 'Settings reads must be blocked while config recovery is quarantined'
    Assert-True ($MigrationContent -match 'gamma_arena_boolean_returns') 'Settings reads must distinguish explicit false-return test adapters from real ini_file_ex nil-success methods'
}

$ConfigTxPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_config_tx.script'
if (Test-Path -LiteralPath $ConfigTxPath) {
    $ConfigTxContent = Get-Content -LiteralPath $ConfigTxPath -Raw
    Assert-True ($ConfigTxContent -match 'line_exist') 'Config transactions must snapshot key presence'
    Assert-True ($ConfigTxContent -match 'r_string_ex') 'Config transactions must snapshot raw values'
    Assert-True ($ConfigTxContent -match 'commit_write_keys') 'Config transactions must commit persistent markers last'
    Assert-True ($ConfigTxContent -match 'commit_remove_keys') 'Config transactions must clear one-shot markers first'
    Assert-True ($ConfigTxContent -match 'fail_closed_keys') 'Config transactions must fail closed for transient intent keys'
    Assert-True ($ConfigTxContent -match 'recover') 'Config transactions must attempt rollback/recovery after mutation failure'
    Assert-True ($ConfigTxContent -match 'config\.ini') 'Recovery must use the raw ini_file_ex backing object for touched-key restoration'
    Assert-True ($ConfigTxContent -match 'config\.cache') 'Recovery must synchronize the ini_file_ex wrapper cache for touched keys'
    Assert-True (([regex]::Matches($ConfigTxContent, 'synchronize_cache\s*\(')).Count -ge 3) 'Successful primary transactions and recovery must both invalidate touched cache entries'
    Assert-True ($ConfigTxContent -match 'GA_CONFIG_QUARANTINED') 'Incomplete recovery must quarantine later Arena transactions'
    Assert-True ($ConfigTxContent -match 'GA_CONFIG_RECOVERY_FAILED') 'Recovery failures must be distinct from primary transaction failures'
    Assert-True ($ConfigTxContent -match 'boolean_returns') 'Explicit false-return failure semantics must be opt-in for adapters'
    Assert-True ($ConfigTxContent -match 'if\s+value\s*==\s*nil\s+then\s+value\s*=\s*""\s+end') 'A present ini_file_ex key with an engine-nil blank value must snapshot as an empty string'
    Assert-True ($ConfigTxContent -match 'local function _snapshot_unchecked') 'Transactions must use a private unchecked snapshot only after their quarantine guard'
    Assert-True ($ConfigTxContent -match '(?s)function snapshot\s*\(\s*config\s*,\s*section\s*,\s*keys\s*\)\s*if is_quarantined\s*\(\s*config\s*\)') 'The public config snapshot API must reject quarantined configs'
}

$StorePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script'
if (Test-Path -LiteralPath $StorePath) {
    $StoreContent = Get-Content -LiteralPath $StorePath -Raw
    Assert-True ($StoreContent -match 'LAUNCH_TOKEN_TTL\s*=\s*600') 'Launch token TTL must be 600 seconds'
    Assert-True ($StoreContent -match 'DEFEAT_TOKEN_TTL\s*=\s*600') 'Defeat token TTL must be 600 seconds'
    foreach ($Api in @('arm_defeat','confirm_defeat','peek_defeat','consume_defeat','issue_launch_from_defeat','clear_defeat')) {
        Assert-True ($StoreContent -match ("function\s+Store:" + $Api)) "Session store must expose defeat API $Api"
        Assert-True ($StoreContent -match ("function\s+" + $Api + "\s*\(")) "Session module must expose defeat wrapper $Api"
    }
    Assert-True ($StoreContent -match 'gad1:') 'Defeat token must use the gad1:<epoch>:<nonce> grammar'
    Assert-True ($StoreContent -match 'function Store:arm_defeat[\s\S]{0,900}local existing = self:read_defeat[\s\S]{0,900}if existing\.value then[\s\S]{0,900}self:defeat_nonce_value') 'Duplicate defeat arm must return the persisted intent before allocating a nonce'
    Assert-True ($StoreContent -match 'ga1:') 'Launch token must use the ga1:<epoch>:<nonce> grammar'
    Assert-True ($StoreContent -match 'volatile_launch_permits') 'Same-VM launch activation must retain its process-local volatile permit fast path'
    Assert-True ($StoreContent -match 'validate_launch_handoff') 'Cross-VM launch activation must validate a persisted bridge lease'
    Assert-True ($StoreContent -match 'reconcile_character_creation') 'Migration reconciliation must distinguish an active launch bridge from an orphaned lease'
    Assert-True ($StoreContent -match 'validate_character_creation_lease') 'Bridge preservation must validate the complete character-creation snapshot before migration can retain it'
    Assert-True (([regex]::Matches($MigrationContent, 'gamma_arena_session_store\.reconcile_character_creation\s*\(\s*config\s*\)')).Count -ge 2) 'Migration must reconcile bridge ownership both before and after transient-intent migration'
    Assert-True ($StoreContent -match 'GA_LAUNCH_HANDOFF_REQUIRED') 'Cross-VM launch must reject a missing bridge lease'
    Assert-True ($StoreContent -match 'GA_LAUNCH_HANDOFF_INVALID') 'Cross-VM launch must reject a mismatched bridge token'
    Assert-True ($StoreContent -match 'GA_LAUNCH_STALE_CLEARED') 'A fresh SessionStore must clear and report orphaned launch intents'
    Assert-True ($StoreContent -match 'validate_persisted_launch_request') 'Same-store pending launch must validate its complete persisted request before duplicate rejection'
    Assert-True ($StoreContent -match 'validate_expected_session') 'Resume consumption must validate the complete expected ArenaSession'
    Assert-True ($StoreContent -match 'GA_RESUME_CHECKPOINT_MISMATCH') 'Resume consumption must bind the reserved checkpoint name'
    Assert-True ($StoreContent -match 'GA_RESUME_FIGHT_INDEX_MISMATCH') 'Resume consumption must reject a next_fight_index older than the ArenaSession checkpoint baseline'
    Assert-True ($StoreContent -notmatch 'session\.value\.fight_index\s*~=\s*intent\.value\.next_fight_index') 'Resume consumption must permit an external next_fight_index newer than the clean checkpoint baseline'
    Assert-True ($StoreContent -match 'intent\.value\.next_fight_index\s*<\s*session\.value\.fight_index') 'Resume consumption must reject an index older than the clean checkpoint baseline'
    Assert-True ($StoreContent -match 'GA_SESSION_GENERATOR_VERSION_INVALID') 'Resume consumption must reject incompatible generator versions'
    Assert-True ($StoreContent -match 'gamma_arena_config_tx\.run') 'Session writes must use the crash-safe config transaction adapter'
    Assert-True ($StoreContent -match 'gamma_arena_boolean_returns') 'Session reads must distinguish explicit false-return test adapters from real ini_file_ex nil-success methods'
    Assert-True ($StoreContent -match 'if\s+value\s*==\s*nil\s+then\s+value\s*=\s*""\s+end') 'Present empty ini_file_ex values must normalize engine nil to an empty string'
    Assert-True ($StoreContent -match 'GA_RESUME_ALREADY_PENDING') 'Session store must not overwrite a pending resume intent'
    Assert-True (([regex]::Matches($StoreContent, 'GA_INTENT_CONFLICT')).Count -ge 4) 'Launch/resume issuance and consumption must reject intent conflicts'
    Assert-True ($ConfigTxContent -match 'remove_line') 'Transient and optional character-creation keys must use transactional remove_line operations'
    Assert-True ($StoreContent -notmatch '\btime_global\b') 'Session store must use injected wall-clock/os.time instead of time_global'
    Assert-True ($StoreContent -notmatch '(?is)\bw_value\s*\([^\)]*,\s*nil\s*\)') 'Session store must never use w_value(..., nil)'
    foreach ($Key in @('launch_pending','launch_token','launch_mode_id','launch_difficulty_id','launch_seed_mode','launch_session_seed','launch_stage','launch_deferred_level','launch_target_level','resume_pending','resume_session_id','resume_session_nonce','resume_next_fight_index','resume_checkpoint_name','resume_schema_version','defeat_pending','defeat_token','defeat_schema_version','defeat_stage','defeat_session_id','defeat_session_nonce','defeat_mode_id','defeat_difficulty_id','defeat_issued_at')) {
        Assert-True ($StoreContent -match [regex]::Escape($Key)) "Session store must cover transient key $Key"
    }
    foreach ($Key in @('new_game_difficulty','new_game_economy','new_game_economy_treasure','new_game_character_name','new_game_faction','new_game_map','new_game_money','new_game_loadout','new_game_story_mode','new_game_icon','new_game_hardcore_mode','new_game_hardcore_mode_lives','new_game_hardcore_mode_regenerate','new_game_survival_mode','new_game_azazel_mode','new_game_warfare','new_game_campfire_mode','new_game_conditions_mode','new_game_timer_mode','new_game_opened_routes','new_game_test')) {
        Assert-True ($StoreContent -match [regex]::Escape($Key)) "Character-creation bridge must cover $Key"
    }
    Assert-True ($StoreContent -match 'bridge_pending') 'Character-creation bridge must persist a durable Gamma Arena lease marker'
    Assert-True ($StoreContent -match 'bridge_schema_version') 'Character-creation bridge lease must be schema-versioned'
    Assert-True ($StoreContent -match 'function Store:restore_character_creation') 'Session store must expose idempotent durable bridge restoration'
    Assert-True ($StoreContent -match 'present') 'Bridge lease must preserve exact key presence independently from value'
    Assert-True ($StoreContent -match 'function Store:clear_transient[\s\S]{0,500}restore_character_creation') 'Common transient cleanup must restore the character-creation bridge before clearing intents'
    Assert-True ($StoreContent -match 'function Store:consume_launch[\s\S]{0,3500}restore_character_creation') 'Successful and rejected launch consumption must converge through bridge restoration'
}

$DxmlPath = Join-Path $RepoRoot 'src\gamedata\scripts\modxml_gamma_arena.script'
if (Test-Path -LiteralPath $DxmlPath) {
    $DxmlContent = Get-Content -LiteralPath $DxmlPath -Raw
    Assert-True ($DxmlContent -match 'register\s*\(\s*RegisterScriptCallback\s*\)') 'DXML zero-argument entry point must use the engine registrar'
    Assert-True ($DxmlContent -match 'registrar\s*\(\s*"on_xml_read"') 'DXML bootstrap must register XML handling through its injected registrar'
    Assert-True ($DxmlContent -match 'registrar\s*\(\s*"main_menu_on_init"') 'DXML bootstrap must register the first main-menu callback early'
    Assert-True ($DxmlContent -match 'GA_DXML_REGISTRAR_UNAVAILABLE') 'DXML bootstrap must fail closed when the callback registrar is unavailable'
    Assert-True ($DxmlContent -match 'GA_DXML_REGISTER_FAILED') 'DXML bootstrap must contain callback registration exceptions'
    Assert-True ($DxmlContent -match 'ui\\\\ui_mm_main\.xml') 'DXML handler must accept the canonical full callback path ui\ui_mm_main.xml'
    Assert-True ($DxmlContent -match 'ui\\\\ui_mm_main_16\.xml') 'DXML handler must accept the effective GAMMA 16:9 callback path ui\ui_mm_main_16.xml'
    Assert-True ($DxmlContent -match 'string\.lower') 'DXML handler must normalize callback path case minimally'
    Assert-True ($DxmlContent -match 'string\.gsub') 'DXML handler must normalize callback path separators minimally'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main btn\[name=btn_gamma_arena\]"\s*\)') 'DXML handler must query the exact duplicate guard selector'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main"\s*\)') 'DXML handler must feature-probe menu_main'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main\s*>\s*btn\[name=btn_newgame\]"\s*\)') 'DXML handler must locate the direct New Game child'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main_single btn\[name=btn_gamma_arena_restart\]"\s*\)') 'DXML handler must query the exact in-game restart duplicate guard selector'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main_single"\s*\)') 'DXML handler must feature-probe the live single-player menu'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main_single\s*>\s*btn\[name=btn_ret\]"\s*\)') 'DXML handler must locate the direct Return to Game child'
    Assert-True ($DxmlContent -match 'getElementPosition') 'DXML handler must derive the insertion point from New Game'
    Assert-True ($DxmlContent -match 'new_game_position\s*\+\s*1') 'Arena must be inserted immediately after New Game'
    Assert-True ($DxmlContent -match 'return_position\s*\+\s*1') 'Restart Arena must be inserted immediately after Return to Game'
    Assert-True ($DxmlContent -notmatch 'menu\[1\]\s*,\s*#menu\[1\]\.kids') 'Arena insertion must not use an end-relative menu position'
    foreach ($Code in @('GA_DXML_POSITION_API_UNAVAILABLE','GA_DXML_MENU_MISSING','GA_DXML_NEW_GAME_MISSING','GA_DXML_NEW_GAME_PARENT_MISMATCH','GA_DXML_NEW_GAME_POSITION_INVALID')) {
        Assert-True ($DxmlContent -match [regex]::Escape($Code)) "DXML placement must fail closed with $Code"
    }
    Assert-True (([regex]::Matches($DxmlContent, '<btn name="btn_gamma_arena" caption="st_gamma_arena_main_menu"\s*/>')).Count -eq 1) 'DXML module must contain exactly one Arena button insertion'
    Assert-True (([regex]::Matches($DxmlContent, '<btn name="btn_gamma_arena_restart" caption="st_gamma_arena_restart"\s*/>')).Count -eq 1) 'DXML module must contain exactly one in-game Arena restart insertion'
    Assert-True ($DxmlContent -match 'insertFromXMLString') 'DXML handler must insert through insertFromXMLString'
    Assert-True ($DxmlContent -match 'pcall\s*\(\s*(gamma_arena_log\.error|logger)\s*,\s*result\.error\.code\s*,\s*result\.error\.message\s*,\s*result\.error\.context') 'DXML callback must internally log structured failures because callback returns are ignored'
}

$Task4DevTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_migrations.script'
if (Test-Path -LiteralPath $Task4DevTestPath) {
    $Task4DevTestContent = Get-Content -LiteralPath $Task4DevTestPath -Raw
    Assert-True ($Task4DevTestContent -match 'character_creation_bridge_accepts_engine_nil_for_present_empty_values') 'Task 4 Dev tests must cover engine nil for present empty character-creation values'
    foreach ($Marker in @('stale_launch_is_recovered_by_new_store','launch_survives_vm_reload_with_matching_bridge_lease','launch_handoff_rejects_mismatched_or_expired_lease','serialized_launch_requires_fake_start_phase_proof','same_store_corrupt_launch_is_replaced','resume_rejects_tampered_expected_session','mutation_failure_matrix_is_crash_safe','recovery_failure_quarantines_transaction','read_and_false_return_faults_are_safe','stale_cleanup_and_conflict_faults_are_safe','matching_resume_cleanup_is_session_scoped','custom_session_cleanup_without_resume_skips_catalog_validation','prepared_resume_consume_rejects_persisted_drift','dxml_accepts_canonical_callback_path','dxml_registers_both_arena_menu_clicks','main_menu_restart_is_acceptance_gated','dxml_registration_failures_are_structured','dxml_places_arena_after_new_game','dxml_placement_failures_are_structured','character_creation_bridge_restores_exactly_from_fresh_store','ordinary_character_creation_without_lease_is_untouched','character_creation_bridge_restores_on_every_launch_terminal_route','character_creation_bridge_faults_fail_closed','start_game_failures_restore_bridge_immediately','arm_fault','arm_read_fault','arm_recovery_fault','persisted')) {
        Assert-True ($Task4DevTestContent -match $Marker) "Task 4 Dev tests must cover $Marker"
    }
    foreach ($Marker in @('defeat_intent_is_transactional_and_cross_vm_safe','defeat_promotion_is_atomic_and_conflict_safe','gad1:1000:death_1','issue_launch_from_defeat')) {
        Assert-True ($Task4DevTestContent -match [regex]::Escape($Marker)) "Task 4 Dev tests must cover defeat contract $Marker"
    }
    Assert-True ($Task4DevTestContent -match 'defeat_duplicate_arm_uses_persisted_token') 'Task 4 Dev tests must cover default-nonce duplicate defeat arm idempotency'
}

$MainMenuPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_main_menu.script'
if (Test-Path -LiteralPath $MainMenuPath) {
    $MainMenuContent = Get-Content -LiteralPath $MainMenuPath -Raw
    Assert-True ($MainMenuContent -match '(?m)^function\s+on_main_menu_init\s*\(') 'Main-menu adapter must export its main_menu_on_init bridge'
    Assert-True ($MainMenuContent -notmatch '(?m)^function\s+on_game_start\s*\(') 'Main-menu adapter must not register after the first cold-start init'
    Assert-True ($MainMenuContent -notmatch 'RegisterScriptCallback') 'Main-menu adapter registration must be owned by the early DXML bootstrap'
    Assert-True ($MainMenuContent -match 'type\s*\(\s*menu\.AddCallback\s*\)\s*==\s*"function"') 'Main-menu adapter must feature-probe AddCallback'
    Assert-True ($MainMenuContent -match 'AddCallback\s*\(\s*"btn_gamma_arena"\s*,\s*ui_events\.BUTTON_CLICKED') 'Main-menu adapter must bind btn_gamma_arena'
    Assert-True ($MainMenuContent -match 'AddCallback\s*\(\s*"btn_gamma_arena_restart"\s*,\s*ui_events\.BUTTON_CLICKED') 'Main-menu adapter must bind the in-game Arena restart button'
    Assert-True ($MainMenuContent -match '(?m)^function\s+request_restart\s*\(') 'Main-menu adapter must expose a testable restart seam'
    Assert-True ($MainMenuContent -match 'request_restart[\s\S]{0,1800}OnButton_return_game') 'Accepted restart must close the pause menu through the stock return action'
    foreach ($Code in @('GA_ARENA_RESTART_UNAVAILABLE','GA_ARENA_RESTART_FAILED','GA_ARENA_RESTART_RESULT_INVALID','GA_ARENA_RESTART_MENU_CLOSE_FAILED')) {
        Assert-True ($MainMenuContent -match [regex]::Escape($Code)) "Main-menu restart adapter must fail closed with $Code"
    }
    Assert-True ($MainMenuContent -notmatch 'ui_main_menu') 'Main-menu adapter must not monkey-patch ui_main_menu'
}

$UiScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_start.script'
if (Test-Path -LiteralPath $UiScriptPath) {
    $UiContent = Get-Content -LiteralPath $UiScriptPath -Raw
    foreach ($Api in @('CScriptXmlInit','InitStatic','InitTextWnd','InitEditBox','Init3tButton','InitComboBox','Register','AddCallback','StartGame')) {
        Assert-True ($UiContent -match $Api) "Start UI must use native API $Api"
    }
    Assert-True ($UiContent -match 'ShowFatal') 'Start UI must expose fatal-error mode'
    Assert-True ($UiContent -match 'fatal_main_menu') 'Fatal mode must expose exactly one main-menu action seam'
    Assert-True ($UiContent -match 'GA_LAUNCH_STALE_CLEARED') 'Start UI must retry once after an atomically cleared stale launch'
    Assert-True ($UiContent -match 'local\s+function\s+retry_stale[\s\S]{0,500}return\s+issue\(\)') 'Start UI stale recovery must perform a fresh launch issuance attempt'
    Assert-True ($UiContent -match 'function\s+invoke_fatal_main_menu') 'Fatal UI must expose a total callback-result propagation seam'
    Assert-True ($UiContent -match 'return\s+invoke_fatal_main_menu') 'Fatal UI action must propagate the disconnect Result to its caller'
    Assert-True ($UiContent -match 'function\s+handoff_start_game') 'Start UI must expose a total engine-handoff seam for behavioral fault injection'
    Assert-True ($UiContent -match 'detail\s*==\s*false') 'Start UI must treat explicit false StartGame as a structured failure'
    Assert-True ($UiContent -match 'begin_start\s*\(\s*self\.owner\s*,\s*axr_main\.config\s*,\s*request\.value\s*,\s*self\.ports\s*\)') 'OnStart must route engine handoff through the preflight-gated common start seam'
}

$UiXmlPath = Join-Path $RepoRoot 'src\gamedata\configs\ui\gamma_arena_start.xml'
if (Test-Path -LiteralPath $UiXmlPath) {
    [xml]$UiXml = Get-Content -LiteralPath $UiXmlPath -Raw
    foreach ($Id in @('gamma_arena_start','title','difficulty','seed','random_seed','validation','start','back','fatal','fatal_text','fatal_main_menu')) {
        Assert-True ($null -ne $UiXml.SelectSingleNode("//*[local-name()='$Id']")) "Start UI XML is missing control $Id"
    }
    Assert-True (@($UiXml.SelectNodes("//*[local-name()='fatal']/*[local-name()='fatal_main_menu']")).Count -eq 1) 'Fatal UI must contain exactly one main-menu action'
    Assert-True ($null -eq $UiXml.SelectSingleNode("/*[local-name()='w']/*[local-name()='gamma_arena_start']/*[local-name()='texture']")) 'Start UI root must not tile a widget texture across the screen'
    $ArenaBackground = $UiXml.SelectSingleNode("/*[local-name()='w']/*[local-name()='gamma_arena_start']/*[local-name()='auto_static'][*[local-name()='texture' and normalize-space(text())='ui\ui_actor_main_menu_one']]")
    Assert-True ($null -ne $ArenaBackground) 'Start UI must use the proven full-screen Anomaly new-game background'
    if ($null -ne $ArenaBackground) {
        Assert-True ($ArenaBackground.GetAttribute('x') -eq '0' -and $ArenaBackground.GetAttribute('y') -eq '0' -and $ArenaBackground.GetAttribute('width') -eq '1024' -and $ArenaBackground.GetAttribute('height') -eq '768' -and $ArenaBackground.GetAttribute('stretch') -eq '1') 'Start UI background must cover the virtual 1024x768 canvas exactly once'
    }
}

foreach ($Locale in @('rus','eng')) {
    $LocalePath = Join-Path $RepoRoot "src\gamedata\configs\text\$Locale\st_gamma_arena.xml"
    if (Test-Path -LiteralPath $LocalePath) {
        $LocaleEncoding = if ($Locale -eq 'rus') { [Text.Encoding]::GetEncoding(1251) } else { [Text.UTF8Encoding]::new($false, $true) }
        [xml]$LocaleXml = $LocaleEncoding.GetString([IO.File]::ReadAllBytes($LocalePath))
        $MenuNode = $LocaleXml.SelectSingleNode('//string[@id="st_gamma_arena_main_menu"]/text')
        Assert-True ($null -ne $MenuNode -and $MenuNode.InnerText -ceq 'ARENA') "$Locale main-menu caption must be exactly ARENA"
    foreach ($Id in @('st_gamma_arena_title','st_gamma_arena_difficulty_rookie','st_gamma_arena_difficulty_stalker','st_gamma_arena_difficulty_veteran','st_gamma_arena_difficulty_master','st_gamma_arena_random_seed','st_gamma_arena_start','st_gamma_arena_back','st_gamma_arena_fatal_title','st_gamma_arena_fatal_error_line','st_gamma_arena_fatal_main_menu','st_gamma_arena_seed_invalid','st_gamma_arena_manual_save_disabled','st_gamma_arena_result_victory','st_gamma_arena_result_defeat','st_gamma_arena_result_main_menu','st_gamma_arena_result_next','st_gamma_arena_result_new_fight')) {
            Assert-True ($null -ne $LocaleXml.SelectSingleNode("//string[@id='$Id']/text")) "$Locale localization is missing $Id"
        }
    }
}

$RussianLocalePath = Join-Path $RepoRoot 'src\gamedata\configs\text\rus\st_gamma_arena.xml'
if (Test-Path -LiteralPath $RussianLocalePath) {
    $RussianBytes = [IO.File]::ReadAllBytes($RussianLocalePath)
    $StrictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    $RussianIsUtf8 = $true
    try { $null = $StrictUtf8.GetString($RussianBytes) } catch { $RussianIsUtf8 = $false }
    Assert-True (-not $RussianIsUtf8) 'Russian localization must use the Windows-1251 byte encoding expected by Anomaly/GAMMA'
    [xml]$RussianXml = [Text.Encoding]::GetEncoding(1251).GetString($RussianBytes)
    $RussianContent = (@($RussianXml.SelectNodes('//text')) | ForEach-Object { $_.InnerText }) -join "`n"
    $RussianExpected = @(
        (ConvertFrom-Json '"\u041d\u043e\u0432\u0438\u0447\u043e\u043a"'),
        (ConvertFrom-Json '"\u0421\u0442\u0430\u043b\u043a\u0435\u0440"'),
        (ConvertFrom-Json '"\u0412\u0435\u0442\u0435\u0440\u0430\u043d"'),
        (ConvertFrom-Json '"\u041c\u0430\u0441\u0442\u0435\u0440"'),
        ((ConvertFrom-Json '"\u0421\u043b\u0443\u0447\u0430\u0439\u043d\u044b\u0439"') + ' seed'),
        (ConvertFrom-Json '"\u041d\u0410\u0427\u0410\u0422\u042c"'),
        (ConvertFrom-Json '"\u041d\u0410\u0417\u0410\u0414"'),
        (ConvertFrom-Json '"\u0412 \u0433\u043b\u0430\u0432\u043d\u043e\u0435 \u043c\u0435\u043d\u044e"'),
        (ConvertFrom-Json '"\u0412\u044b \u043f\u043e\u0433\u0438\u0431\u043b\u0438"'),
        (ConvertFrom-Json '"\u0421\u043b\u0435\u0434\u0443\u044e\u0449\u0438\u0439 \u0431\u043e\u0439"'),
        (ConvertFrom-Json '"\u041f\u043e\u0431\u0435\u0434\u0430"')
    )
    foreach ($Text in $RussianExpected) {
        Assert-True ($RussianContent.Contains($Text)) "Russian localization must contain exact Windows-1251 text: $Text"
    }
}

$EnglishRestartPath = Join-Path $RepoRoot 'src\gamedata\configs\text\eng\st_gamma_arena.xml'
$RussianRestartPath = Join-Path $RepoRoot 'src\gamedata\configs\text\rus\st_gamma_arena_restart.xml'
if (Test-Path -LiteralPath $EnglishRestartPath) {
    [xml]$EnglishRestartXml = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($EnglishRestartPath))
    $EnglishRestart = $EnglishRestartXml.SelectSingleNode('//string[@id="st_gamma_arena_restart"]/text')
    Assert-True ($null -ne $EnglishRestart -and $EnglishRestart.InnerText -ceq 'RESTART ARENA') 'English restart caption must be exact'
}
if (Test-Path -LiteralPath $RussianRestartPath) {
    $RussianRestartBytes = [IO.File]::ReadAllBytes($RussianRestartPath)
    Assert-True (($RussianRestartBytes | Where-Object { $_ -gt 127 }).Count -eq 0) 'Russian restart localization source must remain ASCII-safe Windows-1251 XML'
    [xml]$RussianRestartXml = [Text.Encoding]::GetEncoding(1251).GetString($RussianRestartBytes)
    $RussianRestart = $RussianRestartXml.SelectSingleNode('//string[@id="st_gamma_arena_restart"]/text')
    $RussianRestartExpected = ConvertFrom-Json '"\u041f\u0415\u0420\u0415\u0417\u0410\u041f\u0423\u0421\u0422\u0418\u0422\u042c \u0410\u0420\u0415\u041d\u0423"'
    Assert-True ($null -ne $RussianRestart -and $RussianRestart.InnerText -ceq $RussianRestartExpected) 'Russian restart caption must be exact'
}

$GitAttributesPath = Join-Path $RepoRoot '.gitattributes'
if (Test-Path -LiteralPath $GitAttributesPath) {
    $GitAttributesContent = Get-Content -LiteralPath $GitAttributesPath -Raw
    Assert-True ($GitAttributesContent -match '(?m)^src/gamedata/configs/text/rus/st_gamma_arena\.xml\s+-text\s*$') 'Git must preserve Russian localization bytes without text conversion'
}

$SessionSchemaPath = Join-Path $RepoRoot 'schemas\session-v1.md'
if (Test-Path -LiteralPath $SessionSchemaPath) {
    $SessionSchemaContent = Get-Content -LiteralPath $SessionSchemaPath -Raw
    foreach ($Term in @('session_nonce','checkpoint_name','resume_session_nonce','FightSpec','FightRegistry','ResumeIntent','non-durable','ga1:<issued_at_epoch>:<nonce>','600')) {
        Assert-True ($SessionSchemaContent -match [regex]::Escape($Term)) "Session schema must document $Term"
    }
}

$Task5RuntimeFiles = @(
    'src\gamedata\scripts\gamma_arena_bootstrap.script',
    'src\gamedata\scripts\gamma_arena_compat.script',
    'src\gamedata\scripts\gamma_arena_orchestrator.script',
    'dev\gamedata\scripts\gamma_arena_test_runtime.script'
)
foreach ($RelativePath in $Task5RuntimeFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)) "Task 5 runtime contract is missing: $RelativePath"
}

$Task5BootstrapPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script'
if (Test-Path -LiteralPath $Task5BootstrapPath) {
    $Task5BootstrapContent = Get-Content -LiteralPath $Task5BootstrapPath -Raw
    foreach ($Marker in @('function Registrar:runtime_status', 'function runtime_status', 'last_result', 'GA_BOOTSTRAP_NOT_READY', 'GA_BOOTSTRAP_COMPOSE_FAILED')) {
        Assert-True ($Task5BootstrapContent.Contains($Marker)) "Bootstrap runtime readiness must cover $Marker"
    }
    Assert-True ($Task5BootstrapContent -match 'type\(result\.error\)\s*~=\s*"table"\s+or\s+type\(result\.error\.code\)\s*~=\s*"string"\s+or\s+type\(result\.error\.message\)\s*~=\s*"string"') 'Bootstrap registration Result validation must reject malformed failed error shapes'
    foreach ($Callback in @('on_game_load','actor_on_first_update','actor_on_update','actor_on_before_death','actor_on_death','npc_on_net_spawn','npc_on_death_callback','save_state','load_state','on_before_save_input','on_before_load_input','actor_on_net_destroy','on_before_level_changing')) {
        Assert-True ($Task5BootstrapContent -match ('"' + [regex]::Escape($Callback) + '"')) "Bootstrap registration table must contain $Callback"
    }
    Assert-True ($Task5BootstrapContent -notmatch 'main_menu_on_quit') 'Bootstrap must not treat closing MCM/main menu as quitting Arena'
    Assert-True ($Task5BootstrapContent -notmatch 'main_menu_on_init') 'Task 5 bootstrap must not duplicate the Task 4 main-menu callback'
    Assert-True ($Task5BootstrapContent -match 'reconcile\s*=\s*overrides\.reconcile\s+or\s+function\s*\(\s*config\s*\)[\s\S]{0,200}gamma_arena_migrations\.migrate') 'Production bootstrap must inject migration/reconciliation into every orchestrator'
    Assert-True ($Task5BootstrapContent -match 'current_level') 'Production bootstrap must inject a protected current-level probe'
    Assert-True ($Task5BootstrapContent -match 'local\s+store\s*=\s*overrides\.store\s+or\s+gamma_arena_session_store\.new_store\s*\(\s*\)') 'Production bootstrap must inject the complete session-store instance without a manually mirrored method list'
    Assert-True ($Task5BootstrapContent -notmatch 'module_store_port') 'Production bootstrap must not maintain a second manually mirrored session-store interface'
    foreach ($Marker in @('invoke_callback','new_registrar','register_all','UnregisterScriptCallback','GA_BOOTSTRAP_REGISTRATION_POISONED','rollback')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Bootstrap hardening must cover $Marker"
    }
    Assert-True ($Task5BootstrapContent -match 'pcall') 'Bootstrap callbacks must contain exceptions'
    Assert-True ($Task5BootstrapContent -match 'if\s+not\s+active\s+then\s+return\s+end') 'Inactive runtime-effect callbacks must return before delegation'
    Assert-True ($Task5BootstrapContent -match 'result\.ok\s*==\s*false') 'Bootstrap boundary must route structured Result failures'
    Assert-True ($Task5BootstrapContent -match 'return\s+callback\(\)') 'Bootstrap fatal UI closure must propagate main-menu action results'
    Assert-True ($Task5BootstrapContent -match 'local\s+function\s+teardown_adapter_method') 'Runtime teardown must retain the neutral adapter-method helper after checkpoint removal'
    Assert-True ($Task5BootstrapContent -match 'teardown_adapter_method\(entity_adapter,\s*"cleanup"\)') 'Entity teardown must call the defined neutral adapter-method helper'
    Assert-True ($Task5BootstrapContent -match 'teardown_adapter_method\(actor_adapter,\s*"cleanup"\)') 'Actor teardown must call the defined neutral adapter-method helper'
    Assert-True ($Task5BootstrapContent -notmatch '\bteardown_method\s*\(') 'Removed checkpoint helper name must not remain as an undefined active teardown call'
}

$Task5CompatPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script'
if (Test-Path -LiteralPath $Task5CompatPath) {
    $Task5CompatContent = Get-Content -LiteralPath $Task5CompatPath -Raw
    foreach ($Capability in @('RegisterScriptCallback','UnregisterScriptCallback','ini_file','system_ini','alife','alife_create','alife_create_item','alife_release_id','se_save_var','level.patrol_path_exists','patrol','db.actor','axr_main.config','safe_release_manager.release')) {
        Assert-True ($Task5CompatContent -match [regex]::Escape($Capability)) "Preflight must probe $Capability"
    }
    Assert-True ($Task5CompatContent -notmatch 'set_invulnerable|\.invulnerable') 'Natural actor death preflight must not require an invulnerability port'
    foreach ($Marker in @('l05_bar','AI_STL_S','arena_enemy','point','level_vertex_id','game_vertex_id','4294967295','GA_PREFLIGHT_PATROL_MISSING','GA_PREFLIGHT_PATROL_INVALID','GA_PREFLIGHT_SECTION_MISSING','GA_NPC_CLASS_API_MISSING','GA_NPC_CLASS_MISSING','GA_NPC_CLASS_READ_FAILED','GA_NPC_CLASS_INVALID','GA_NPC_COMMUNITY_API_MISSING','GA_NPC_COMMUNITY_MISSING','GA_NPC_COMMUNITY_READ_FAILED','GA_NPC_COMMUNITY_INVALID')) {
        Assert-True ($Task5CompatContent -match [regex]::Escape($Marker)) "Preflight must enforce $Marker"
    }
    Assert-True ($Task5CompatContent -match 'engine_callable_present') 'Preflight must accept callable engine objects whose Lua type is not function'
    Assert-True ($Task5CompatContent -notmatch 'type\(p\.ini_file\)\s*==\s*["'']function["'']') 'Preflight must not reject the callable ini_file engine object by Lua type'
    Assert-True ($Task5CompatContent -notmatch 'type\(p\.patrol\)\s*==\s*["'']function["'']') 'Preflight must not reject the callable patrol engine object by Lua type'
    foreach ($Marker in @('npc_medical_ini','medkits','bandages','GA_NPC_MEDICAL_AI_CONFLICT')) {
        Assert-True ($Task5CompatContent -match [regex]::Escape($Marker)) "NPC medical compatibility preflight must cover $Marker"
    }
}

$Task5OrchestratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script'
if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    $Task5OrchestratorContent = Get-Content -LiteralPath $Task5OrchestratorPath -Raw
    foreach ($Marker in @('inspect_intents','consume_launch','gamma_arena_session','st_gamma_arena_manual_save_disabled','GA_INTENT_CONFLICT','GA_RESUME_UNSUPPORTED','GA_LAUNCH_REQUIRES_NEW_GAME','disconnect','pending_load_state','awaiting_activation','on_callback_result_error','GA_DISCONNECT_FAILED','main_menu_executed')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Orchestrator must cover $Marker"
    }
    foreach ($Forbidden in @('math.random','math.randomseed')) {
        Assert-True ($Task5OrchestratorContent -notmatch [regex]::Escape($Forbidden)) "Task 5 orchestrator must not contain $Forbidden"
    }
    Assert-True ($Task5OrchestratorContent -match 'GA_FIGHT_INDEX_EXHAUSTED') 'Fight-index exhaustion must have a stable structured runtime code'
    Assert-True ($Task5OrchestratorContent -match 'GA_DEPENDENCY_METHOD_UNAVAILABLE') 'Missing dependency methods must use a dedicated error code instead of a domain launch code'
    Assert-True ($Task5OrchestratorContent -match 'requested_code\s*=\s*code') 'Missing dependency diagnostics must preserve the requested operation code as context'
    $FatalStart = $Task5OrchestratorContent.IndexOf('function Orchestrator:enter_fatal')
    $FatalEnd = $Task5OrchestratorContent.IndexOf('function Orchestrator:on_callback_error')
    Assert-True ($FatalStart -ge 0 -and $FatalEnd -gt $FatalStart) 'Orchestrator fatal block must remain structurally testable'
    if ($FatalStart -ge 0 -and $FatalEnd -gt $FatalStart) {
        $FatalContent = $Task5OrchestratorContent.Substring($FatalStart, $FatalEnd - $FatalStart)
        Assert-True ($FatalContent -match 'self\.activation_attempted\s*=\s*true') 'Fatal routing must latch the activation attempt'
        Assert-True ($FatalContent -match 'self\.awaiting_activation\s*=\s*false') 'Fatal routing must stop per-frame activation retries'
    }
    $ActivationStart = $Task5OrchestratorContent.IndexOf('function Orchestrator:activate_once')
    $ActivationEnd = $Task5OrchestratorContent.IndexOf('function Orchestrator:layout_snapshot')
    $ActivationContent = $Task5OrchestratorContent.Substring($ActivationStart, $ActivationEnd - $ActivationStart)
    Assert-True ($ActivationContent.IndexOf('self.deps.reconcile') -ge 0) 'First activation must invoke the injected migration/reconciliation dependency'
    Assert-True ($ActivationContent.IndexOf('self.deps.reconcile') -lt $ActivationContent.IndexOf('inspect_intents')) 'Migration/reconciliation must complete before intent inspection'
    Assert-True ($ActivationContent -match 'GA_SETTINGS_RECONCILIATION_FAILED') 'Thrown/invalid activation reconciliation must use a structured wrapper code'
    Assert-True ($ActivationContent -match 'route\s*=\s*"deferred"') 'Launch activation must expose a non-consuming wrong-level deferred route'
    Assert-True ($ActivationContent -match 'mark_launch_deferred') 'fake_start deferral must persist a cross-VM phase proof'
    Assert-True ($ActivationContent -match 'validate_launch_activation') 'serialized target-level activation must validate its fake_start phase proof'
    $WrongLevelStart = $ActivationContent.IndexOf('if current.value ~= expected then')
    $DeferredRoute = $ActivationContent.IndexOf('route = "deferred"', $WrongLevelStart)
    $LaunchActivationLatch = $ActivationContent.IndexOf('self.activation_attempted = true', $DeferredRoute)
    Assert-True ($WrongLevelStart -ge 0 -and $DeferredRoute -gt $WrongLevelStart -and $LaunchActivationLatch -gt $DeferredRoute) 'Wrong-level deferral must precede the launch one-shot activation latch'
    Assert-True ($ActivationContent -match 'if\s+not\s+state\.launch_pending[\s\S]{0,450}self\.activation_attempted\s*=\s*true[\s\S]{0,150}self\.awaiting_activation\s*=\s*false') 'Ordinary games without Arena intents must latch their activation probe once'
    Assert-True ($Task5OrchestratorContent -match 'was_active\s*==\s*true\s+or\s+self:is_active\(\)') 'A callback that activates and then fails must enter fatal routing'
    foreach ($Marker in @('GA_LAUNCH_DEFERRED','GA_LAUNCH_HANDOFF_ACCEPTED','GA_RUNTIME_STAGE_CHANGED','GA_ACTOR_POSITIONED','GA_ACTOR_LOADOUT_APPLIED','GA_OPPONENTS_ACTIVATED')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Production event diagnostics must cover $Marker"
    }
    Assert-True ($Task5OrchestratorContent -match 'deferred_level_logged') 'Wrong-level launch diagnostics must be deduplicated instead of logging every frame'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:actor_on_death\s*\(\s*\)') 'Natural actor death callback must expose the no-argument Anomaly signature'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:actor_on_before_death[\s\S]{0,1200}arm_defeat') 'Before-death handling must arm the persisted cross-VM defeat intent'
    $Task5BeforeDeathBlock = [regex]::Match($Task5OrchestratorContent, 'function\s+Orchestrator:actor_on_before_death[\s\S]*?[\r\n]+end').Value
    Assert-True ($Task5BeforeDeathBlock -notmatch 'ret_value|hold_after_logical_death|normalize_status|health') 'Arena before-death handling must never cancel lethal damage or mutate the dying actor'
    Assert-True ($Task5OrchestratorContent -notmatch 'function\s+Orchestrator:(show_defeat|defeat_next_action)') 'Natural death must remove the in-level logical-defeat UI and retry path'
    foreach ($Marker in @('npc_medical','start_npc_medical','update_npc_medical','stop_npc_medical')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Orchestrator must compose NPC medical lifecycle marker $Marker"
    }
}

$Task5StorePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script'
if (Test-Path -LiteralPath $Task5StorePath) {
    $Task5StoreContent = Get-Content -LiteralPath $Task5StorePath -Raw
    Assert-True ($Task5StoreContent -match 'GA_SESSION_UNKNOWN_FIELD') 'ArenaSession validator must reject unknown/future fields'
    Assert-True ($Task5StoreContent -match 'function Store:inspect_intents') 'Session store must expose non-mutating intent inspection'
    Assert-True ($Task5StoreContent -match 'function Store:prepare_resume') 'Session store must validate a resume route before checkpoint re-hide'
    Assert-True ($Task5StoreContent -match 'function Store:clear_resume_if_matches') 'Checkpoint cleanup must clear only a ResumeIntent bound to its ArenaSession'
    $ClearResumeStart = $Task5StoreContent.IndexOf('function Store:clear_resume_if_matches')
    $ClearResumeEnd = $Task5StoreContent.IndexOf('function Store:clear_transient', $ClearResumeStart)
    $ClearResumeContent = $Task5StoreContent.Substring($ClearResumeStart, $ClearResumeEnd - $ClearResumeStart)
    Assert-True ($ClearResumeContent.IndexOf('if not pending.value then return gamma_arena_result.ok(false) end') -lt $ClearResumeContent.IndexOf('validate_expected_session(expected)')) 'Resume cleanup must skip Custom catalog validation when no resume intent exists.'
    Assert-True ($Task5StoreContent -match 'function Store:consume_resume\s*\(\s*config\s*,\s*expected\s*,\s*prepared') 'Resume consumption must compare the persisted intent with its prepared snapshot'
    Assert-True ($Task5StoreContent -match 'launch_handoff') 'Launch consumption must expose non-secret handoff metadata for diagnostics'
    foreach ($Marker in @('launch_stage','function Store:mark_launch_deferred','function Store:validate_launch_activation')) {
        Assert-True ($Task5StoreContent -match [regex]::Escape($Marker)) "Serialized new-game handoff must cover $Marker"
    }
    $PrepareResumeStart = $Task5StoreContent.IndexOf('function Store:prepare_resume')
    $ConsumeResumeStart = $Task5StoreContent.IndexOf('function Store:consume_resume')
    $PrepareResumeContent = $Task5StoreContent.Substring($PrepareResumeStart, $ConsumeResumeStart - $PrepareResumeStart)
    Assert-True ($PrepareResumeContent -match 'GA_CHECKPOINT_RECOVERY_MISMATCH') 'Resume preparation mismatches must use the limited checkpoint recovery taxonomy'
    Assert-True ($PrepareResumeContent -notmatch 'GA_RESUME_(SESSION|NONCE|CHECKPOINT|FIGHT_INDEX)_MISMATCH') 'Resume preparation must not leak legacy GA_RESUME mismatch codes'
    Assert-True ($PrepareResumeContent -match 'normalize_prepare_session_result\s*\(\s*validate_expected_session') 'Resume preparation must normalize validation-time checkpoint mismatch codes'
}

$Task5DevTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script'
if (Test-Path -LiteralPath $Task5DevTestPath) {
    $Task5DevTestContent = Get-Content -LiteralPath $Task5DevTestPath -Raw
    $RuntimeBootstrapStatusRegistration = [PSCustomObject]@{ Name = 'runtime_bootstrap_status_preserves_initialization_result'; Function = 'runtime_bootstrap_status_preserves_initialization_result' }
    $RuntimeBootstrapStatusPattern = '\{\s*name\s*=\s*"' + [regex]::Escape($RuntimeBootstrapStatusRegistration.Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($RuntimeBootstrapStatusRegistration.Function) + '\s*\}'
    Assert-True ($Task5DevTestContent -match $RuntimeBootstrapStatusPattern) "Regression case must be registered exactly: $($RuntimeBootstrapStatusRegistration.Name) -> $($RuntimeBootstrapStatusRegistration.Function)."
    foreach ($Marker in @('runtime_preflight_accepts_natural_death_without_invulnerability','runtime_preflight_aggregates_in_stable_order','runtime_preflight_requires_task6_actor_checkpoint_ports','runtime_preflight_requires_community_for_every_custom_profile','runtime_preflight_requires_human_class_for_every_custom_profile','runtime_preflight_rejects_missing_profile_value_apis','runtime_preflight_normalizes_effective_arena_enemy_community','runtime_wrong_level_skips_patrol_resolution','runtime_launch_consumes_before_preflight_once','runtime_activation_requires_game_load_boundary','runtime_launch_defers_on_fake_start_then_activates_on_rostok','runtime_ordinary_no_intent_activation_latches_once','runtime_first_activation_failure_routes_fatal','runtime_activation_reconciles_before_intent_inspection_once','runtime_activation_version_changes_clear_resume_before_checkpoint_routing','runtime_activation_reconciliation_failures_are_fatal_before_inspection','runtime_invalid_or_expired_launch_never_reaches_preflight','runtime_ordinary_loaded_save_rejects_stray_launch','runtime_ordinary_loaded_save_rejects_stray_resume','runtime_new_game_does_not_reuse_prior_load_state_latch','runtime_game_load_boundary_drops_prior_runtime_generation','runtime_config_quarantine_propagates_to_fatal','runtime_save_payload_is_plain_deep_copy','runtime_manual_save_and_load_flags_are_blocked','runtime_callback_boundary_routes_exceptions_once','runtime_callback_boundary_routes_false_results_once','runtime_inactive_callback_results_remain_benign','runtime_active_save_failure_enters_fatal_once','runtime_fatal_main_menu_retries_throw_then_becomes_idempotent','runtime_fatal_main_menu_retries_explicit_false','runtime_fatal_ui_helper_propagates_callback_results','runtime_bootstrap_registration_rolls_back_every_position','runtime_bootstrap_registration_poison_blocks_retry','runtime_bootstrap_requires_unregister_before_composition','runtime_unexpected_net_destroy_clears_external_route','runtime_orchestrator_npc_net_spawn_is_active_only','runtime_npc_net_spawn_errors_defer_fatal_ui_to_update','runtime_entity_net_spawn_isolates_only_owned_npcs','runtime_entity_net_spawn_fails_closed_on_owner_and_community_faults','runtime_entity_activation_rejects_runtime_community_drift')) {
        Assert-True ($Task5DevTestContent -match $Marker) "Task 5 Dev tests must cover $Marker"
    }
}

$Task9UiScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_result.script'
$Task9UiXmlPath = Join-Path $RepoRoot 'src\gamedata\configs\ui\gamma_arena_result.xml'
Assert-True (Test-Path -LiteralPath $Task9UiScriptPath) 'Task 9 result/countdown UI adapter is missing'
Assert-True (Test-Path -LiteralPath $Task9UiXmlPath) 'Task 9 result/countdown UI XML is missing'
if (Test-Path -LiteralPath $Task9UiScriptPath) {
    $Task9UiContent = Get-Content -LiteralPath $Task9UiScriptPath -Raw
    foreach ($Marker in @('class "UIResult" (CUIScriptWnd)','show_countdown','clear_countdown','show_result','clear_result','ClearOwnedWidgets','__finalize','st_gamma_arena_result_defeat','st_gamma_arena_result_victory','DIK_RETURN','DIK_SPACE','DIK_ESCAPE','OnNext','OnMainMenu')) {
        Assert-True ($Task9UiContent -match [regex]::Escape($Marker)) "Task 9 UI must cover $Marker"
    }
    Assert-True ($Task9UiContent -notmatch 'AddCustomStatic') 'Task 9 UI must never reference an undefined custom-static id'
    Assert-True ($Task9UiContent -match 'OnKeyboard[\s\S]{0,500}self:OnMainMenu\(\)[\s\S]{0,120}return\s+true') 'Task 9 Escape handler must route cleanup and return an engine boolean'
    Assert-True ($Task9UiContent -match 'next_button:TextControl\(\):SetText') 'Result primary button captions must use the native CUI3tButton TextControl API'
    Assert-True ($Task9UiContent -notmatch 'next_button:SetText') 'Result primary button captions must not call the unavailable CUI3tButton SetText method directly'
    Assert-True ($Task9UiContent -match 'resolve_result_keyboard_action[\s\S]{0,500}DIK_RETURN[\s\S]{0,240}DIK_SPACE[\s\S]{0,160}return\s+["'']next["''][\s\S]{0,600}OnKeyboard[\s\S]{0,400}action\s*==\s*["'']next["''][\s\S]{0,160}self:OnNext\(\)[\s\S]{0,120}return\s+true') 'Task 9 result keyboard fallback must route Enter/Space to the next-fight action'
    Assert-True ($Task9UiContent -match 'ShowCountdown[\s\S]{0,900}model\.on_main_menu[\s\S]{0,900}self\.on_main_menu') 'Task 9 countdown UI must retain the common Arena main-menu callback'
    Assert-True ($Task9UiContent -notmatch 'OnMainMenu[\s\S]{0,240}kind\s*==\s*["'']countdown["'']') 'Task 9 main-menu action must not reject countdown Escape'
}
if (Test-Path -LiteralPath $Task9UiXmlPath) {
    try {
        [xml]$Task9UiXml = Get-Content -LiteralPath $Task9UiXmlPath -Raw
        foreach ($Id in @('gamma_arena_result','countdown','result_panel','title','next','main_menu')) {
            Assert-True ($null -ne $Task9UiXml.SelectSingleNode("//*[local-name()='$Id']")) "Task 9 UI XML is missing control $Id"
        }
        Assert-True ($null -eq $Task9UiXml.SelectSingleNode("/*[local-name()='w']/*[local-name()='gamma_arena_result']/*[local-name()='texture']")) 'Task 9 UI root must not stretch or tile a widget texture across the screen'
    } catch { Assert-True $false "Task 9 UI XML must parse: $($_.Exception.Message)" }
}

$CustomSetupUiScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_custom.script'
Assert-True (Test-Path -LiteralPath $CustomSetupUiScriptPath) 'Custom setup UI adapter is missing'
if (Test-Path -LiteralPath $CustomSetupUiScriptPath) {
    $CustomSetupUiContent = Get-Content -LiteralPath $CustomSetupUiScriptPath -Raw
    Assert-True (([regex]::Matches($CustomSetupUiContent, 'self\.faction_button:TextControl\(\):SetText\s*\(')).Count -eq 2) 'Custom setup faction label branches must use the native CUI3tButton text control API'
    Assert-True ($CustomSetupUiContent -notmatch 'self\.faction_button:SetText\s*\(') 'Custom setup faction labels must not call the unavailable CUI3tButton SetText method directly'
}

$BattleUiScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_battle.script'
$BattleUiXmlPath = Join-Path $RepoRoot 'src\gamedata\configs\ui\gamma_arena_battle.xml'
$BattleUiEngPath = Join-Path $RepoRoot 'src\gamedata\configs\text\eng\st_gamma_arena.xml'
$BattleUiRusPath = Join-Path $RepoRoot 'src\gamedata\configs\text\rus\st_gamma_arena.xml'
Assert-True (Test-Path -LiteralPath $BattleUiScriptPath) 'Battle identity HUD adapter is missing'
Assert-True (Test-Path -LiteralPath $BattleUiXmlPath) 'Battle identity HUD XML is missing'
if (Test-Path -LiteralPath $BattleUiScriptPath) {
    $BattleUiContent = Get-Content -LiteralPath $BattleUiScriptPath -Raw
    foreach ($Marker in @('class "UIBattleIdentity" (CUIScriptWnd)','format_identity','main_hud_visible','sync_visibility','report_visibility_failure_once','initialization_result','registration_confirmed','cleanup_pending','rollback_partial_add','show_identity','clear_identity','AddDialogToRender','RemoveDialogToRender','main_hud_shown')) {
        Assert-True ($BattleUiContent -match [regex]::Escape($Marker)) "Battle identity HUD must cover $Marker"
    }
    Assert-True ($BattleUiContent -notmatch 'initialization_result\s*=\s*sync_visibility') 'Battle identity visibility failure must not overwrite successful text initialization'
    Assert-True ($BattleUiContent -notmatch 'ShowDialog') 'Battle identity HUD must never become a modal dialog'
    Assert-True ($BattleUiContent -notmatch 'AddCustomStatic|RemoveCustomStatic') 'Battle identity HUD must not mutate shared custom statics'
    Assert-True ($BattleUiContent -match 'local\s+SEPARATOR\s*=\s*" \| "') 'Battle identity must use an ASCII pipe separator'
    Assert-True ($BattleUiContent -notmatch 'string\.char\(194,\s*183\)') 'Battle identity must not emit a UTF-8 middle-dot separator'
}
if (Test-Path -LiteralPath $BattleUiXmlPath) {
    try {
        [xml]$BattleUiXml = Get-Content -LiteralPath $BattleUiXmlPath -Raw
        foreach ($Id in @('gamma_arena_battle','panel','identity')) {
            Assert-True ($null -ne $BattleUiXml.SelectSingleNode("//*[local-name()='$Id']")) "Battle identity HUD XML is missing control $Id"
        }
        $BattlePanel = $BattleUiXml.SelectSingleNode("//*[local-name()='panel']")
        $BattleIdentity = $BattleUiXml.SelectSingleNode("//*[local-name()='identity']")
        $BattleText = $BattleIdentity.SelectSingleNode("*[local-name()='text']")
        Assert-True ([int]$BattlePanel.x + [int]$BattlePanel.width -eq 994) 'Battle identity HUD must retain the approved right safe-area inset'
        Assert-True ($null -eq $BattlePanel.SelectSingleNode("*[local-name()='texture']")) 'Battle identity HUD panel must be fully transparent'
        Assert-True ($BattleText.r -eq '255' -and $BattleText.g -eq '255' -and $BattleText.b -eq '255') 'Battle identity HUD text must be pure white'
    } catch { Assert-True $false "Battle identity HUD XML must parse: $($_.Exception.Message)" }
}
foreach ($TextPath in @($BattleUiEngPath, $BattleUiRusPath)) {
    Assert-True (Test-Path -LiteralPath $TextPath) "Battle identity localization file is missing: $TextPath"
    if (Test-Path -LiteralPath $TextPath) {
        $BattleText = Get-Content -LiteralPath $TextPath -Raw
        foreach ($Id in @('st_gamma_arena_battle_seed','st_gamma_arena_battle_fight')) {
            Assert-True ($BattleText -match [regex]::Escape($Id)) "Battle identity localization must define $Id in $TextPath"
        }
    }
}
$BattleRuntimeTests = Get-Content -LiteralPath $Task5DevTestPath -Raw
foreach ($Marker in @('runtime_battle_identity_formatter_is_exact','runtime_battle_identity_adapter_owns_one_window','runtime_battle_identity_removal_failure_is_retryable','runtime_battle_identity_initialization_failure_prevents_registration','runtime_battle_identity_partial_add_is_rolled_back_or_retryable','runtime_battle_identity_main_hud_visibility_is_safe','runtime_battle_identity_visibility_sync_is_structured','runtime_battle_identity_visibility_failure_reporting_is_bounded')) {
    Assert-True ($BattleRuntimeTests -match [regex]::Escape($Marker)) "Battle identity runtime tests must cover $Marker"
}
Assert-True ($BattleRuntimeTests -match [regex]::Escape('gamma_arena_test_assert.equals(env.added.text, "Fight: 2 | Seed: 42", "existing battle identity window refreshes")')) 'Battle identity refresh fixture must require fight-first ASCII text'
$BattleOrchestratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script'
$BattleBootstrapPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script'
$BattleOrchestratorContent = Get-Content -LiteralPath $BattleOrchestratorPath -Raw
$BattleBootstrapContent = Get-Content -LiteralPath $BattleBootstrapPath -Raw
foreach ($Marker in @('show_battle_identity','clear_battle_identity','GA_BATTLE_IDENTITY_MISMATCH','GA_BATTLE_UI_SHOW_FAILED','GA_BATTLE_UI_CLEAR_FAILED')) {
    Assert-True ($BattleOrchestratorContent -match [regex]::Escape($Marker)) "Battle identity lifecycle must cover $Marker"
}
foreach ($Marker in @('gamma_arena_ui_battle.new','battle_ui')) {
    Assert-True ($BattleBootstrapContent -match [regex]::Escape($Marker)) "Battle identity bootstrap must cover $Marker"
}
Assert-True ($BattleBootstrapContent -match 'GA_BATTLE_UI_VISIBILITY_UPDATE_FAILED') 'Battle identity visibility failures must reach bounded runtime diagnostics'
foreach ($Marker in @('runtime_battle_identity_lifecycle_is_active_only','runtime_battle_identity_failures_are_classified','runtime_battle_identity_mismatch_fails_before_active','runtime_battle_identity_accepts_full_uint32_session_seed')) {
    Assert-True ($BattleRuntimeTests -match [regex]::Escape($Marker)) "Battle identity lifecycle tests must cover $Marker"
}
Assert-True ($BattleOrchestratorContent -match 'seed\.value\s*<\s*0[\s\S]{0,80}seed\.value\s*>=\s*UINT32_MOD' -and $BattleOrchestratorContent -notmatch 'seed\.value\s*<\s*1') 'Battle identity runtime must accept the full uint32 ArenaSession seed domain.'
Assert-True ($BattleUiContent -match 'model\.session_seed\s*<\s*0[\s\S]{0,80}model\.session_seed\s*>\s*UINT32_MAX' -and $BattleUiContent -notmatch 'PARK_MILLER_MAX') 'Battle identity HUD must format the full uint32 ArenaSession seed domain.'

$Task6MainMenuPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_main_menu.script'
$Task6UiStartPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_start.script'
$Task6TextPath = Join-Path $RepoRoot 'src\gamedata\configs\text\rus\st_gamma_arena.xml'
if (Test-Path -LiteralPath $Task6MainMenuPath) {
    $Task6MainMenuContent = Get-Content -LiteralPath $Task6MainMenuPath -Raw
    Assert-True ($Task6MainMenuContent -match '(?m)^function\s+show_confirmed_defeat\s*\(') 'Task 6 main-menu adapter must expose the confirmed-defeat controller'
    foreach ($Marker in @('peek_defeat','consume_defeat','issue_launch_from_defeat','random_session_seed','write_character_creation','handoff_start_game','st_gamma_arena_result_new_fight','show_fatal','clear_transient')) {
        Assert-True ($Task6MainMenuContent -match [regex]::Escape($Marker)) "Task 6 defeat controller must cover $Marker"
    }
    Assert-True ($Task6MainMenuContent -notmatch '\bdb\.actor\b') 'Task 6 menu-side defeat flow must never dereference the destroyed actor'
    Assert-True ($Task6MainMenuContent -notmatch 'Anomaly|load_game|load_save|checkpoint|resume|revive') 'Task 6 fresh-fight action must use only the engine new-game handoff'
    Assert-True ($Task6MainMenuContent -match 'if\s+not\s+shown\.ok\s+then[\s\S]{0,600}clear_result[\s\S]{0,600}clear_defeat[\s\S]{0,600}restore_main_menu') 'Failed defeat-result construction must dismiss partial UI and clear its confirmed intent before restoring the stock menu'
    Assert-True ($Task6MainMenuContent -match 'if\s+not\s+shown\s+then[\s\S]{0,500}restore_main_menu\s*\(\s*menu') 'Task 6 fatal-UI construction failure must restore the owner menu as a fallback'
    Assert-True ($Task6MainMenuContent -match 'model\.on_main_menu\s*=\s*function\(\)[\s\S]{0,900}local\s+cleared[\s\S]{0,500}local\s+restored\s*=\s*restore_main_menu') 'Task 6 post-consume UI handling must attempt owner restoration even when result dismissal fails'
    Assert-True ($Task6MainMenuContent -match 'local\s+defeat_consumed\s*=\s*false') 'Task 6 main-menu action must latch successful defeat consumption across UI retries'
    Assert-True ($Task6MainMenuContent -match 'restore_main_menu[\s\S]{0,500}menu:ShowDialog\(true\)[\s\S]{0,180}menu:Show\(true\)[\s\S]{0,350}dialog:HideDialog\(\)') 'Task 6 owner restoration must succeed before dismissing its recovery dialog'
    Assert-True ($Task6MainMenuContent -match 'GA_DEFEAT_MENU_HIDE_FAILED[\s\S]{0,900}show_fatal') 'Task 6 partial menu-hide failure must retain fatal recovery when owner restoration fails'
    Assert-True ($Task6MainMenuContent -match 'if\s+not\s+shown\s+then[\s\S]{0,260}local\s+fallback\s*=\s*restore_main_menu\s*\(\s*menu\s*\)[\s\S]{0,500}Partial main-menu hide recovery') 'Task 6 fatal construction failure after partial hide must retry owner restoration'
    Assert-True ($Task6MainMenuContent -match '(?m)^function\s+defer_confirmed_defeat\s*\(') 'Confirmed defeat must expose a post-construction deferral seam'
    Assert-True ($Task6MainMenuContent -match 'local\s+original_update\s*=\s*menu\.Update[\s\S]{0,900}menu\.Update\s*=\s*function[\s\S]{0,900}original_update\s*\(') 'Confirmed defeat must run only after the stock main-menu Update begins'
    Assert-True ($Task6MainMenuContent -match 'deferred_menus\s*\[\s*menu\s*\]\s*=\s*nil[\s\S]{0,700}pcall\s*\(\s*show_confirmed_defeat') 'Deferred defeat must be removed before its one-shot display attempt'
    Assert-True ($Task6MainMenuContent -match 'if\s+not\s+result\.ok\s+then[\s\S]{0,260}recover_unexpected_deferred_failure') 'Every ordinary deferred-display failure must fail open through complete recovery'
    Assert-True ($Task6MainMenuContent -match 'if\s+not\s+peeked\.ok\s+then[\s\S]{0,260}recover_unexpected_deferred_failure') 'Scheduling-time defeat read failures must fail open through complete recovery'
    Assert-True ($Task6MainMenuContent -match 'clear_result[\s\S]{0,400}clear_fatal[\s\S]{0,400}clear_defeat[\s\S]{0,400}restore_main_menu') 'Deferred recovery must dismiss every Arena modal, clear defeat state, and restore the stock menu'
    $Task6RandomPreflightIndex = $Task6MainMenuContent.IndexOf('local runtime_preflight = port_or_default(ports, "runtime_preflight", gamma_arena_ui_start.preflight_runtime)')
    $Task6RandomPreflightRecoveryIndex = $Task6MainMenuContent.IndexOf('if not runtime.ok then return recover_from_fresh_failure(menu, ports, config, runtime, false) end', $Task6RandomPreflightIndex + 1)
    $Task6RandomSeedIndex = $Task6MainMenuContent.IndexOf('local random_session_seed = port_or_default(ports, "random_session_seed", gamma_arena_session_store.random_session_seed)', $Task6RandomPreflightRecoveryIndex + 1)
    Assert-True ($Task6RandomPreflightIndex -ge 0 -and $Task6RandomPreflightRecoveryIndex -gt $Task6RandomPreflightIndex -and $Task6RandomSeedIndex -gt $Task6RandomPreflightRecoveryIndex) 'Confirmed-defeat random rematches must preflight before seed generation and preserve transient launch state on readiness failure'
    Assert-True ($Task6MainMenuContent -match 'local\s+function\s+recover_from_fresh_failure\s*\([^\)]*clear_transient[^\)]*\)[\s\S]{0,500}if\s+clear_transient\s+then[\s\S]{0,500}end') 'Fresh-fight recovery must make transient clearing explicit for preflight failures'
    $Task6BindIndex = $Task6MainMenuContent.IndexOf('bind(menu)')
    $Task6DefeatIndex = $Task6MainMenuContent.IndexOf('defer_confirmed_defeat(menu', $Task6BindIndex + 1)
    Assert-True ($Task6BindIndex -ge 0 -and $Task6DefeatIndex -gt $Task6BindIndex) 'Task 6 main-menu init must bind normally before deferring the confirmed defeat'
}
if (Test-Path -LiteralPath $Task9UiScriptPath) {
    Assert-True ($Task9UiContent -match 'next_title_key') 'Task 6 result UI must accept a primary-action title key'
    Assert-True ($Task9UiContent -match 'st_gamma_arena_result_new_fight') 'Task 6 result UI must validate the defeat-specific primary label'
    Assert-True ($Task9UiContent -match 'next_button:TextControl\(\):SetText\s*\(') 'Task 6 result UI must apply the translated primary-action label through the native button text control'
    Assert-True ($Task9UiContent -match 'if\s+self\.action_locked[\s\S]{0,180}return\s+gamma_arena_result\.ok\(false\)') 'Task 6 result actions must retain the repeated-click lock'
    Assert-True ($Task9UiContent -match '(?m)^function\s+resolve_result_keyboard_action\s*\(') 'Task 6 result keyboard routing must expose a behavioral test seam'
    Assert-True ($Task9UiContent -match '(?m)^function\s+dismiss_result_window\s*\(') 'Task 6 result dismissal must expose its retry-safe behavioral seam'
    Assert-True ($Task9UiContent -match '(?m)^function\s+invoke_active_main_menu\s*\(') 'Task 6 runtime tests must drive Main menu through the public active-result action'
    Assert-True ($Task9UiContent -match 'function\s+dismiss_result_window[\s\S]{0,900}HideDialog[\s\S]{0,300}Show\(false\)[\s\S]{0,900}ClearOwnedWidgets') 'Task 6 result dismissal must preserve its model until engine hiding succeeds'
    $Task6DismissStart = $Task9UiContent.IndexOf('function dismiss_result_window')
    $Task6DismissClear = $Task9UiContent.IndexOf('window:ClearOwnedWidgets()', $Task6DismissStart)
    $Task6DismissActiveClear = $Task9UiContent.IndexOf('active_window = nil', $Task6DismissStart)
    Assert-True ($Task6DismissStart -ge 0 -and $Task6DismissClear -gt $Task6DismissStart -and $Task6DismissActiveClear -gt $Task6DismissClear) 'Task 6 result dismissal must retain the module active window until owned-widget cleanup succeeds'
}
if (Test-Path -LiteralPath $Task6UiStartPath) {
    $Task6UiStartContent = Get-Content -LiteralPath $Task6UiStartPath -Raw
    Assert-True ($Task6UiStartContent -match '(?m)^function\s+handoff_start_game\s*\(') 'Task 6 must expose the shared StartGame handoff'
    Assert-True ($Task6UiStartContent -match '(?m)^function\s+clear_fatal\s*\(') 'Task 6 must expose fail-open dismissal for a partial fatal dialog'
}
if (Test-Path -LiteralPath $Task6UiStartPath) {
    $Task6UiStartContent = Get-Content -LiteralPath $Task6UiStartPath -Raw
    Assert-True ($Task6UiStartContent -match '(?m)^function\s+issue_launch_with_defeat_recovery\s*\(') 'Arena start UI must expose bounded confirmed-defeat conflict recovery'
    Assert-True ($Task6UiStartContent -match 'GA_INTENT_CONFLICT[\s\S]{0,1000}peek_defeat[\s\S]{0,1000}clear_defeat[\s\S]{0,1000}retry_stale\s*\(\s*issue\(\)\s*\)') 'Arena start recovery must classify, clear, and retry only a confirmed defeat conflict'
}
$Task3UiStartPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_start.script'
if (Test-Path -LiteralPath $Task3UiStartPath) {
    $Task3UiStartContent = Get-Content -LiteralPath $Task3UiStartPath -Raw
    Assert-True ($Task3UiStartContent -match '(?m)^function\s+preflight_runtime\s*\(') 'Ordinary Arena start must expose runtime readiness preflight.'
    Assert-True ($Task3UiStartContent -match '(?m)^function\s+begin_start\s*\(') 'Ordinary Arena start must expose a centralized start seam.'
    Assert-True ($Task3UiStartContent -match '(?m)^function\s+initialize_settings\s*\(') 'Start UI must expose its settings initialization decision for runtime regression coverage.'
    $Task3Constructor = [regex]::Match($Task3UiStartContent, '(?ms)^function\s+UIStart:__init\s*\([^\)]*\)(.*?)^end\s*$').Value
    Assert-True ($Task3Constructor -match 'initialize_settings\s*\(\s*self\s*,\s*self\.ports\s*\)') 'Start UI construction must route settings initialization through the fatal-only guard.'
    $Task3InitializeSettings = [regex]::Match($Task3UiStartContent, '(?ms)^function\s+initialize_settings\s*\([^\)]*\)(.*?)^end\s*$').Value
    Assert-True ($Task3InitializeSettings -match 'ports\.fatal_only\s*==\s*true[\s\S]{0,160}return\s+false[\s\S]{0,240}dialog:LoadSettings\s*\(\s*\)') 'Fatal-only UI construction must return before LoadSettings while ordinary construction still loads settings.'
    $Task3ShowFatal = [regex]::Match($Task3UiStartContent, '(?ms)^function\s+show_fatal\s*\([^\)]*\)(.*?)^end\s*$').Value
    Assert-True ($Task3ShowFatal -match 'create\s*\(\s*owner\s*,\s*\{\s*fatal_only\s*=\s*true\s*\}\s*\)') 'Production fatal recovery must request fatal-only UI construction.'
    foreach ($Marker in @('runtime_status', 'GA_START_RUNTIME_UNAVAILABLE', 'GA_START_RUNTIME_STATUS_FAILED', 'GA_START_RUNTIME_STATUS_INVALID')) {
        Assert-True ($Task3UiStartContent.Contains($Marker)) "Ordinary Arena start runtime preflight must cover $Marker"
    }
    foreach ($Port in @('save_preferences', 'issue_launch', 'write_character_creation')) {
        Assert-True ($Task3UiStartContent -match ('ports\.' + [regex]::Escape($Port))) "Ordinary Arena start must inject $Port for behavioral ordering tests."
    }
    $Task3BeginStart = [regex]::Match($Task3UiStartContent, '(?ms)^function\s+begin_start\s*\([^\)]*\)(.*?)^end\s*$').Value
    $Task3PreflightIndex = $Task3BeginStart.IndexOf('preflight_runtime(ports)')
    $Task3PreferenceIndex = $Task3BeginStart.IndexOf('save_preferences')
    $Task3LaunchIndex = $Task3BeginStart.IndexOf('issue_launch_with_defeat_recovery')
    $Task3BridgeIndex = $Task3BeginStart.IndexOf('write_character_creation')
    $Task3HandoffIndex = $Task3BeginStart.IndexOf('handoff_start_game')
    Assert-True ($Task3PreflightIndex -ge 0 -and $Task3PreferenceIndex -gt $Task3PreflightIndex -and $Task3LaunchIndex -gt $Task3PreferenceIndex -and $Task3BridgeIndex -gt $Task3LaunchIndex -and $Task3HandoffIndex -gt $Task3BridgeIndex) 'Ordinary Arena start must preflight before preferences, launch, bridge, and StartGame handoff.'
    $Task3OnStart = [regex]::Match($Task3UiStartContent, '(?ms)^function\s+UIStart:OnStart\s*\(\)(.*?)^end\s*$').Value
    Assert-True ($Task3OnStart -match 'begin_start\s*\(\s*self\.owner\s*,\s*axr_main\.config\s*,\s*request\.value\s*,\s*self\.ports\s*\)') 'OnStart must delegate ordinary handoff through the preflight-gated start seam.'
}
$Task3RuntimeTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
$Task3Registration = '\{\s*name\s*=\s*"runtime_ordinary_start_preflight_precedes_mutation"\s*,\s*fn\s*=\s*runtime_ordinary_start_preflight_precedes_mutation\s*\}'
Assert-True ($Task3RuntimeTests -match $Task3Registration) 'Regression case must be registered exactly: runtime_ordinary_start_preflight_precedes_mutation -> runtime_ordinary_start_preflight_precedes_mutation.'
$FatalOnlyRegistration = '\{\s*name\s*=\s*"runtime_defeat_menu_default_fatal_path_skips_start_settings"\s*,\s*fn\s*=\s*runtime_defeat_menu_default_fatal_path_skips_start_settings\s*\}'
Assert-True ($Task3RuntimeTests -match $FatalOnlyRegistration) 'Regression case must be registered exactly: runtime_defeat_menu_default_fatal_path_skips_start_settings -> runtime_defeat_menu_default_fatal_path_skips_start_settings.'
if (Test-Path -LiteralPath $Task6TextPath) {
    [xml]$Task6Text = Get-Content -LiteralPath $Task6TextPath -Raw
    Assert-True ($null -ne $Task6Text.SelectSingleNode("//*[local-name()='string' and @id='st_gamma_arena_result_new_fight']")) 'Task 6 localization must define the New fight label'
}
if (Test-Path -LiteralPath $Task4DevTestPath) {
    foreach ($Marker in @('defeat_main_menu_fresh_fight_promotes_once','defeat_main_menu_exit_consumes_without_launch')) {
        Assert-True ($Task4DevTestContent -match [regex]::Escape($Marker)) "Task 6 migration tests must cover $Marker"
    }
}
if (Test-Path -LiteralPath $Task5DevTestPath) {
    $RuntimeDefeatPreflightRegistration = [PSCustomObject]@{ Name = 'runtime_defeat_menu_fresh_failures_are_bounded'; Function = 'runtime_defeat_menu_fresh_failures_are_bounded' }
    $RuntimeDefeatPreflightPattern = '\{\s*name\s*=\s*"' + [regex]::Escape($RuntimeDefeatPreflightRegistration.Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($RuntimeDefeatPreflightRegistration.Function) + '\s*\}'
    Assert-True ($Task5DevTestContent -match $RuntimeDefeatPreflightPattern) "Regression case must be registered exactly: $($RuntimeDefeatPreflightRegistration.Name) -> $($RuntimeDefeatPreflightRegistration.Function)."
    $RuntimeDefeatPreflightIdentityRegistration = [PSCustomObject]@{ Name = 'runtime_defeat_menu_preflight_failure_identity_is_preserved'; Function = 'runtime_defeat_menu_preflight_failure_identity_is_preserved' }
    $RuntimeDefeatPreflightIdentityPattern = '\{\s*name\s*=\s*"' + [regex]::Escape($RuntimeDefeatPreflightIdentityRegistration.Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($RuntimeDefeatPreflightIdentityRegistration.Function) + '\s*\}'
    Assert-True ($Task5DevTestContent -match $RuntimeDefeatPreflightIdentityPattern) "Regression case must be registered exactly: $($RuntimeDefeatPreflightIdentityRegistration.Name) -> $($RuntimeDefeatPreflightIdentityRegistration.Function)."
    foreach ($Marker in @('GA_BOOTSTRAP_COMPOSE_FAILED','use_default','result_type','preflight failure generates no seed','preflight failure does not clear transient state')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Confirmed-defeat preflight identity test must cover $Marker"
    }
    foreach ($Marker in @('runtime_defeat_menu_rejects_invalid_or_expired_handoff','runtime_defeat_menu_fresh_failures_are_bounded','runtime_defeat_menu_exit_retries_consumption_safely','runtime_defeat_menu_fatal_ui_failure_restores_owner','runtime_defeat_result_construction_failure_clears_intent_and_restores_owner','runtime_defeat_menu_post_consume_ui_failure_restores_owner','runtime_defeat_menu_post_consume_restore_failure_is_recoverable','runtime_defeat_recovery_dialog_waits_for_owner_restore','runtime_defeat_partial_clear_never_reconsumes_token','runtime_defeat_partial_owned_widget_clear_never_reconsumes_token','runtime_defeat_partial_hide_restores_or_retains_recovery','runtime_defeat_result_keyboard_and_lock_are_behavioral','runtime_result_primary_button_uses_native_text_control','runtime_start_launch_recovers_only_confirmed_defeat_conflict')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 6 runtime tests must cover $Marker"
    }
}
if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    foreach ($Marker in @('death_latched','defeat_token','arm_defeat','confirm_defeat','neutralize_owned_opponents','NEXT_AFTER_DEFEAT','drive_continuation')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Natural-death orchestrator must cover $Marker"
    }
    Assert-True ($Task5OrchestratorContent -match 'show_countdown["'']\s*,\s*\{[\s\S]{0,500}on_main_menu') 'Task 9 countdown model must route the common Arena main-menu cleanup'
    $Task9VictoryBlock = [regex]::Match($Task5OrchestratorContent, 'function\s+Orchestrator:show_victory\(\)[\s\S]*?[\r\n]+end').Value
    Assert-True ($Task9VictoryBlock -notmatch 'acquire_input') 'Victory result modal must not globally disable mouse input'
    Assert-True ($Task5OrchestratorContent -match 'if\s+state\.resume_pending\s+then[\s\S]{0,300}GA_RESUME_UNSUPPORTED') 'Legacy ResumeIntent must fail safely without checkpoint recovery'
    Assert-True ($Task5OrchestratorContent -notmatch 'checkpoint_restore_failure|normalize_resume_preparation') 'Checkpoint recovery normalizers must be absent from dedicated Arena runtime'
}
$Task9ActorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_actor_adapter.script'
if (Test-Path -LiteralPath $Task9ActorPath) {
    $Task9ActorContent = Get-Content -LiteralPath $Task9ActorPath -Raw
    Assert-True ($Task9ActorContent -match [regex]::Escape('cleanup_loadout_for_restore')) 'Task 9 actor adapter must expose owned-loadout-only cleanup before restore'
    Assert-True ($Task9ActorContent -notmatch 'hold_after_logical_death|release_logical_death_hold|held_after_death') 'Actor adapter must not retain logical-death hold or revival state'
}
if (Test-Path -LiteralPath $Task5DevTestPath) {
    foreach ($Marker in @('runtime_natural_death_arms_confirms_and_neutralizes_once','runtime_natural_death_failures_never_cancel_engine_death','runtime_natural_death_outside_active_arena_is_inert','runtime_entity_death_neutralization_is_owned_living_and_idempotent','runtime_entity_death_neutralization_without_actor_still_clears_enemy','runtime_entity_death_neutralization_aggregates_every_failure','runtime_task9_countdown_escape_model_routes_main_menu_cleanup','runtime_task9_resume_failures_normalize_to_restore_failed','runtime_fight_index_max_minus_one_advances_once','runtime_fight_index_exhaustion_precedes_mutation_and_routes_fatal','runtime_actor_loadout_consumed_absent_id_retires_without_release','runtime_actor_loadout_pre_release_reused_foreign_id_is_never_released','runtime_actor_loadout_post_submit_reuse_is_never_released_twice','runtime_actor_loadout_malformed_ownership_proof_fails_closed','runtime_actor_loadout_exact_owned_match_releases_once','runtime_actor_loadout_apply_failures_never_drop_valid_created_ids','runtime_actor_loadout_failed_tag_write_never_manufactures_ownership','runtime_task9_resume_pending_invalid_loaded_session_normalizes','runtime_task9_restoring_state_read_failure_normalizes','runtime_task9_resume_completion_transition_failure_normalizes')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 9 Dev tests must cover $Marker"
    }
}
if (Test-Path -LiteralPath $Task5BootstrapPath) {
    Assert-True ($Task5BootstrapContent -match 'gamma_arena_ui_result\.new\s*\(') 'Task 9 bootstrap must replace the Task 8 UI placeholder with the real adapter'
    Assert-True ($Task5BootstrapContent -match 'clear_enemy\s*=\s*function\s*\(\s*npc\s*\)[\s\S]{0,220}set_enemy\s*\(\s*nil\s*\)') 'Runtime entity composition must clear only a provided registered NPC enemy target'
    foreach ($Marker in @('ownership_token','save_owner_tag','load_owner_tag','resolve_entity','GA_ACTOR_LOADOUT_OWNERSHIP_MISMATCH')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Task 9 actor loadout cleanup must cover reuse-safe ownership proof: $Marker"
    }
    Assert-True ($Task5BootstrapContent -match 'created\[#created\s*\+\s*1\]\s*=\s*entry[\s\S]{0,500}save_and_verify_tag\(entry\)') 'Task 9 rollback registry must retain every valid unique created id before later proof/tag failure'
    Assert-True (([regex]::Matches($Task5BootstrapContent, 'save_and_verify_tag\(record\)')).Count -eq 1) 'Task 9 ownership tags may be written only during creation, never during cleanup'
    Assert-True ($Task5BootstrapContent -notmatch 'cleanup\s*=\s*function\(\)[\s\S]{0,2600}save_and_verify_tag\(record\)') 'Task 9 cleanup must never write or rewrite an ownership tag'
}

$Task6RuntimeFiles = @(
    'src\gamedata\scripts\gamma_arena_actor_adapter.script',
    'src\gamedata\scripts\gamma_arena_checkpoint_adapter.script'
)
foreach ($RelativePath in $Task6RuntimeFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)) "Task 6 runtime contract is missing: $RelativePath"
}

$Task6ActorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_actor_adapter.script'
if (Test-Path -LiteralPath $Task6ActorPath) {
    $Task6ActorContent = Get-Content -LiteralPath $Task6ActorPath -Raw
    foreach ($Marker in @('normalize_for_arena','verify_inventory_empty','apply_loadout','reset_for_rematch','begin_update','iterate_inventory','"parent"','release_item_id','set_health_ex','set_actor_condition','power','radiation','bleeding','psy_health','give_money','disable_effects_timer','set_actor_position','set_actor_direction','input_owned','GA_ACTOR_INACTIVE')) {
        Assert-True ($Task6ActorContent -match [regex]::Escape($Marker)) "Actor adapter must cover $Marker"
    }
    Assert-True ($Task6ActorContent -notmatch 'function\s+ActorAdapter:enforce_boundary') 'Closed Rostok Arena must not run a per-update actor boundary teleport guard'
    Assert-True ($Task6ActorContent -match 'function\s+ActorAdapter:reset_for_rematch') 'Actor adapter must expose one shared in-memory rematch reset'
    Assert-True ($Task6ActorContent -match 'function\s+ActorAdapter:begin_rematch_boundary') 'Actor adapter must expose an immediate rematch input boundary'
    Assert-True ($Task6ActorContent -match 'function\s+ActorAdapter:reset_transient_state') 'Actor adapter must expose one authoritative transient reset boundary'
    Assert-True ($Task6ActorContent -match 'interrupt_item_use[\s\S]{0,900}acquire_input') 'Item-use interruption must precede Arena input acquisition in the rematch boundary'
    Assert-True ($Task6ActorContent -match 'reset_transient_state[\s\S]{0,1500}loadout\.cleanup') 'Transient cleanup must precede rematch loadout cleanup'
    Assert-True ($Task6ActorContent -match 'function\s+ActorAdapter:normalize_for_arena[\s\S]{0,1300}if\s+acquired\.value\s*==\s*true\s+then[\s\S]{0,220}release_input') 'Normalization rollback may release only an input lease acquired by that invocation'
    Assert-True ($Task6ActorContent -notmatch 'call_actor\s*\(\s*item\s*,\s*["'']parent_id["'']') 'Actor adapter must use the real client game_object parent():id() API, never nonexistent parent_id()'
    Assert-True ($Task6ActorContent -match '"bleeding"\s*,\s*1') 'GAMMA actor normalization must use the observed cured bleeding sentinel 1'
    Assert-True ($Task6ActorContent.Contains('reset_transient_state')) 'Actor adapter must reset GAMMA transient state between rounds'
    foreach ($Forbidden in @('set_power','set_radiation','set_bleeding','set_psy_health')) {
        Assert-True ($Task6ActorContent -notmatch [regex]::Escape($Forbidden)) "Actor adapter must not call nonexistent Anomaly method $Forbidden"
    }
}

$Task6CheckpointPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_checkpoint_adapter.script'
if (Test-Path -LiteralPath $Task6CheckpointPath) {
    $Task6CheckpointContent = Get-Content -LiteralPath $Task6CheckpointPath -Raw
    Assert-True ($Task6CheckpointContent -match 'canonicalize_engine_path') 'Checkpoint engine port must canonicalize trusted update_path results before core validation'
    Assert-True ($Task6CheckpointContent -match 'engine_device_namespace') 'Checkpoint engine port must reject Win32 device namespaces before UNC parsing'
    foreach ($Marker in @('WAITING_STABLE','HIDING','READY','UNHIDING','LOADING','REHIDING','CLEANING','_gamma_arena_checkpoint','.scop','.scoc','.dds','.gamma_arena_hidden','GA_CHECKPOINT_TIMEOUT','GA_CHECKPOINT_UNSAFE_PATH','issue_resume','consume_resume','clear_resume_if_matches','pending_or_timeout','elapsed_ms','engine_fs_port','update_path','file_rename','file_delete','"rb"','save " .. CHECKPOINT_NAME','load " .. CHECKPOINT_NAME')) {
        Assert-True ($Task6CheckpointContent -match [regex]::Escape($Marker)) "Checkpoint adapter must cover $Marker"
    }
    foreach ($Forbidden in @('file_list','file_list_open_ex','file_find')) {
        Assert-True ($Task6CheckpointContent -notmatch [regex]::Escape($Forbidden)) "Checkpoint adapter must not use broad path discovery: $Forbidden"
    }
    foreach ($Marker in @('ERROR','GA_CHECKPOINT_LOAD_TIMEOUT','last_mutation_cause','mutation_attempt')) {
        Assert-True ($Task6CheckpointContent -match [regex]::Escape($Marker)) "Task 6 bounded checkpoint retry must cover $Marker"
    }
    foreach ($Marker in @('begin_resume_recovery','GA_CHECKPOINT_RECOVERY_MISSING','GA_CHECKPOINT_RECOVERY_INCONSISTENT','GA_CHECKPOINT_RECOVERY_MISMATCH','GA_CHECKPOINT_RECOVERY_TIMEOUT','prepared_resume')) {
        Assert-True ($Task6CheckpointContent -match [regex]::Escape($Marker)) "Task 6 fresh-process recovery must cover $Marker"
    }
    Assert-True ($Task6CheckpointContent -match 'target_info\.value\.exists\s+then\s+if\s+required\s+and\s+target_info\.value\.size\s*<=\s*0') 'Required zero-byte rename targets must remain pending after the source disappears'
    foreach ($Marker in @('late_dds_started','GA_CHECKPOINT_DDS_TIMEOUT','pending_late_dds_or_timeout')) {
        Assert-True ($Task6CheckpointContent -match [regex]::Escape($Marker)) "Late optional DDS retries must cover $Marker"
    }
    Assert-True ($Task6CheckpointContent -match 'fs\.exist\s*,\s*fs\s*,\s*"\$game_saves\$"\s*,') 'Checkpoint existence must call the installed X-Ray alias-plus-relative-name signature'
    Assert-True ($Task6CheckpointContent -notmatch 'pcall\(fs\.exist\s*,\s*fs\s*,\s*path\s*\)') 'Checkpoint existence must never pass one absolute path to getFS.exist'
}
$Task6BootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
foreach ($Marker in @('zzz_player_injuries', 'BHS_PARTS', 'bhs.health', 'bhs.maxhp', 'bhs.timedhp', 'utils.save_var', 'utils.load_var', 'mod_body_health_reset')) {
    Assert-True ($Task6BootstrapContent.Contains($Marker)) "Bootstrap GAMMA Body Health integration is missing marker: $Marker"
}
foreach ($Marker in @('lam2.abort','ClearWounds','ClearAllBoosters','WoundForEach','BoosterForEach','ChangeAlcohol','remove_all_psy_ppe_effects','RemoveTimeEvent','set_stage_two','655808','655820','99123','99133','8053','reset_transient_state')) {
    Assert-True ($Task6BootstrapContent.Contains($Marker)) "Round transient reset integration is missing marker: $Marker"
}
Assert-True ($Task6BootstrapContent -notmatch 'GetAlcohol') 'Round transient reset must not depend on the unexported Monolith GetAlcohol method'
Assert-True ($Task6BootstrapContent -match 'runtime_object_method\("GA_ACTOR_ALCOHOL_CLEAR_FAILED",\s*api,\s*"ChangeAlcohol",\s*-1\s*\)') 'Round transient reset must zero the normalized Monolith alcohol range through ChangeAlcohol(-1)'
Assert-True ($Task6BootstrapContent.Contains('GA_ACTOR_BOOSTER_READBACK_STALE')) 'MT-TEST stale booster enumeration must remain nonfatal structured telemetry'
Assert-True ($Task6BootstrapContent -match 'if\s+wound_count\s*~=\s*0\s+then') 'Native wound readback must remain a strict reset postcondition'
Assert-True ($Task6BootstrapContent -notmatch 'wound_count\s*~=\s*0\s+or\s+booster_count\s*~=\s*0') 'Contradictory MT-TEST booster enumeration must not share the fatal wound postcondition'
$RoundTransitionRuntimeContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Name in @('runtime_actor_rematch_boundary_aborts_before_input_lock','runtime_actor_rematch_boundary_failure_never_acquires_input','runtime_actor_preowned_input_survives_normalize_failure','runtime_actor_rematch_transients_clear_once_before_loadout_cleanup','runtime_actor_transient_failure_prevents_loadout_cleanup','runtime_bootstrap_engine_transients_clear_and_verify','runtime_bootstrap_engine_booster_readback_is_nonfatal','runtime_bootstrap_missing_alcohol_mutator_fails_closed','runtime_bootstrap_gamma_transient_integrations_are_exact','runtime_entity_ready_revalidates_items_before_hostility')) {
    Assert-True ($RoundTransitionRuntimeContent.Contains($Name)) "Round transition runtime regression must cover $Name"
}
foreach ($Name in @('runtime_victory_next_locks_before_result_ui_closes','runtime_victory_next_boundary_failure_retains_result','runtime_countdown_waits_for_fully_staged_ready_state','runtime_countdown_deadline_activates_and_releases_in_same_update','runtime_activation_failure_never_releases_input','runtime_manual_and_integrity_transitions_share_boundary')) {
    Assert-True ($RoundTransitionRuntimeContent.Contains($Name)) "Round transition orchestration regression must cover $Name"
}
$VictoryNextStart = $Task5OrchestratorContent.IndexOf('function Orchestrator:victory_next_action')
$VictoryNextEnd = if ($VictoryNextStart -ge 0) { $Task5OrchestratorContent.IndexOf('function Orchestrator:restart_arena_action', $VictoryNextStart) } else { -1 }
Assert-True ($VictoryNextStart -ge 0 -and $VictoryNextEnd -gt $VictoryNextStart) 'Victory-next boundary must remain structurally testable'
if ($VictoryNextStart -ge 0 -and $VictoryNextEnd -gt $VictoryNextStart) {
    $VictoryNextBlock = $Task5OrchestratorContent.Substring($VictoryNextStart, $VictoryNextEnd - $VictoryNextStart)
    $VictoryBoundaryIndex = $VictoryNextBlock.IndexOf('begin_rematch_boundary')
    $VictoryClearIndex = $VictoryNextBlock.IndexOf('clear_result')
    Assert-True ($VictoryBoundaryIndex -ge 0 -and $VictoryClearIndex -gt $VictoryBoundaryIndex) 'Victory-next must acquire the rematch boundary before closing Result UI'
}
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:queue_integrity_retry[\s\S]{0,900}begin_rematch_boundary') 'Integrity retry must acquire the shared rematch boundary before transition mutations'
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:restart_arena_action[\s\S]{0,900}begin_rematch_boundary') 'Manual restart must acquire the shared rematch boundary before transition mutations'
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:is_opponent_activation_allowed\(\)[\s\S]{0,160}runtime_stage\s*==\s*"ACTIVATING"') 'Opponent activation gate must open only in orchestrator ACTIVATING'
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:begin_countdown_after_equipment[\s\S]{0,350}snapshot\.state\s*~=\s*"READY"') 'Visible countdown must wait for the fully staged entity READY state'
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:update_countdown[\s\S]{0,550}set_runtime_stage\("ACTIVATING"\)') 'Countdown deadline must enter the bounded ACTIVATING stage'
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:observe_entity_activation[\s\S]{0,350}stage\s*=\s*"ACTIVATING"') 'Activation observation must remain ACTIVATING until entity ACTIVE is proven'
Assert-True ($Task5OrchestratorContent -match 'GA_ENTITY_UPDATE_FAILED[\s\S]{0,500}runtime_stage\s*==\s*"ACTIVATING"[\s\S]{0,350}observe_entity_activation') 'Orchestrator must observe entity activation again after the entity update'

$CheckpointFreeStatePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_state_machine.script'
if (Test-Path -LiteralPath $CheckpointFreeStatePath) {
    $CheckpointFreeStateContent = Get-Content -LiteralPath $CheckpointFreeStatePath -Raw
    Assert-True ($CheckpointFreeStateContent -match '\[event_values\.PREFLIGHT_SUCCEEDED\]\s*=\s*state_values\.PREPARING') 'Dedicated Arena preflight must advance directly to PREPARING'
    Assert-True ($CheckpointFreeStateContent -match 'RESTART\s*=\s*"RESTART"') 'Arena state graph must expose the manual restart event'
    Assert-True ($CheckpointFreeStateContent -match '\[event_values\.RESTART\]\s*=\s*state_values\.RESULT') 'Active manual restart must enter the existing result continuation boundary'
    Assert-True ($CheckpointFreeStateContent -notmatch 'state_values\.(CHECKPOINTING|RECOVERING)') 'Dedicated Arena state graph must not contain checkpoint or save-recovery states'
}

Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:restart_arena_action\s*\(') 'Orchestrator must expose the manual Arena restart action'
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:restart_arena_action\s*\([\s\S]{0,1800}pending_continuation_kind\s*=\s*"victory_next"') 'Manual Arena restart must reuse the existing next-fight continuation'
Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:restart_arena_action\s*\([\s\S]{0,1500}clear_battle_identity\("manual_restart"\)') 'Manual Arena restart must hide battle identity before leaving active combat'
Assert-True ($Task5BootstrapContent -match '(?m)^function\s+request_restart\s*\(') 'Bootstrap must expose the registered runtime restart bridge'
foreach ($Marker in @('runtime_manual_restart_reuses_next_fight_once','runtime_manual_restart_inactive_and_exhausted_are_inert','runtime_bootstrap_restart_without_registered_runtime_is_inert')) {
    Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Runtime tests must cover $Marker"
}

if (Test-Path -LiteralPath $Task5BootstrapPath) {
    foreach ($Marker in @('gamma_arena_actor_adapter.new','level.disable_input','level.enable_input','safe_release_manager.release')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Task 6 bootstrap composition must cover $Marker"
    }
    foreach ($Marker in @('step_entity_cleanup','step_actor_cleanup','teardown_clock','teardown_timeout_ms','teardown_max_updates','GA_ENTITY_TEARDOWN_TIMEOUT','GA_ENTITY_TEARDOWN_EXHAUSTED','GA_ACTOR_TEARDOWN_TIMEOUT','GA_ACTOR_TEARDOWN_EXHAUSTED')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Bootstrap teardown drain must cover $Marker"
    }
    Assert-True ($Task5BootstrapContent -match 'MAX_TEARDOWN_UPDATES') 'Bootstrap teardown drain must impose a finite hard update cap'
    Assert-True ($Task5BootstrapContent -match 'max_updates\s*>\s*MAX_TEARDOWN_UPDATES') 'Caller-supplied teardown update bounds must not exceed the hard cap'
}

$Task6CompatPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script'
if (Test-Path -LiteralPath $Task6CompatPath) {
    $Task6CompatContent = Get-Content -LiteralPath $Task6CompatPath -Raw
    foreach ($Marker in @('time_global','level.disable_input','level.enable_input','db.actor.iterate_inventory','db.actor.power','db.actor.radiation','db.actor.bleeding','db.actor.psy_health','db.actor.set_actor_position','db.actor.activate_slot','db.actor.active_slot')) {
        Assert-True ($Task6CompatContent -match [regex]::Escape($Marker)) "Task 6 preflight must require $Marker"
    }
    foreach ($Forbidden in @('GA_PREFLIGHT_BOUNDARY_MISSING','GA_PREFLIGHT_BOUNDARY_INVALID')) {
        Assert-True ($Task6CompatContent -notmatch [regex]::Escape($Forbidden)) "Closed Rostok Arena preflight must not require $Forbidden"
    }
}

if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    foreach ($Marker in @('normalize_for_arena','verify_inventory_empty','runtime_stage')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Task 6 orchestration must cover $Marker"
    }
    Assert-True ($Task5OrchestratorContent -notmatch 'gamma_arena_generator') 'FightSpec generation must remain gated out of Task 6'
    foreach ($Marker in @('GA_RUNTIME_CLEANUP_PENDING','cleanup_ready_for_disconnect')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Fatal entity/actor cleanup routing must cover $Marker"
    }
    Assert-True ($Task5OrchestratorContent -match 'self\.cleanup_required\s*=\s*true') 'Fatal routing must gate disconnect on actual entity/actor cleanup even before session assignment'
    Assert-True ($Task5OrchestratorContent -match 'result\.ok\s+and\s+not\s+pending') 'Failed or frame-pending teardown must remain retryable instead of latching completion'
    Assert-True ($Task5OrchestratorContent -match 'self\.teardown_cycle\s*=\s*self\.teardown_cycle\s*\+\s*1') 'A new loaded-game lifecycle must create a fresh teardown cycle'
    Assert-True ($Task5OrchestratorContent -notmatch 'function\s+Orchestrator:enforce_actor_boundary') 'Closed Rostok Arena orchestration must not perform runtime boundary correction'
    Assert-True ($Task5OrchestratorContent -match 'if\s+self\.runtime_stage\s*==\s*"WAIT_INVENTORY"[\s\S]{0,900}self:set_runtime_stage\("PREPARING"\)') 'Empty dedicated Arena inventory must advance directly to PREPARING'
    Assert-True ($Task5OrchestratorContent -notmatch 'GA_CHECKPOINT_CREATE_FAILED') 'Dedicated Arena startup must never create a save checkpoint'
    Assert-True ($Task5OrchestratorContent -match 'pending_continuation_kind\s*=\s*"integrity_retry"') 'Integrity retry must select the bounded exact-fight continuation path'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:drive_continuation') 'Victory and integrity retry must share one bounded continuation transaction'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:drive_continuation[\s\S]{0,5000}pending_continuation_kind[\s\S]{0,5000}begin_apply[\s\S]{0,1500}fight_spec') 'Integrity retry must retain and reapply the immutable FightSpec'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:observe_entity_activation[\s\S]{0,900}release_input') 'Fresh ACTIVE must return player input without a logical-death revival step'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:observe_entity_activation[\s\S]{0,1800}death_latched\s*=\s*false[\s\S]{0,600}result_action_locked\s*=\s*false') 'Fresh ACTIVE must clear the repeated-rematch latches'
    Assert-True ($Task5BootstrapContent -notmatch 'gamma_arena_checkpoint_adapter|default_checkpoint_adapter|checkpoint_adapter|stage\s*=\s*"checkpoint"') 'Dedicated Arena composition and teardown must not bind the checkpoint adapter'
    Assert-True ($Task5OrchestratorContent -notmatch 'deps\.checkpoint|CHECKPOINTING|RESTORING|RESUME_REHIDING|request_checkpoint_restore|expect_checkpoint_reload|checkpoint_ready') 'Dedicated Arena runtime must not contain active checkpoint stages or dependencies'
    Assert-True ($Task6CompatContent -notmatch 'getFS|file_rename|file_delete|exec_console_cmd') 'Checkpoint-only filesystem and console APIs must not gate dedicated Arena preflight'
    Assert-True ($Task6ActorContent -match 'function\s+ActorAdapter:normalize_for_arena') 'Actor normalization must use checkpoint-free Arena terminology'
    Assert-True ($Task6ActorContent -notmatch 'normalize_for_checkpoint') 'Active actor normalization must not retain checkpoint terminology'
}

if (Test-Path -LiteralPath $Task5DevTestPath) {
    foreach ($Marker in @('runtime_actor_inventory_release_is_deferred_and_verified','runtime_actor_normalization_uses_gamma_bleeding_sentinel','runtime_actor_input_ownership_is_idempotent','runtime_actor_rejects_coincident_patrol_points','runtime_checkpoint_requires_stable_required_files','runtime_checkpoint_allows_absent_or_late_dds','runtime_checkpoint_wrap_clock_times_out','runtime_checkpoint_verifies_rename_and_delete_postconditions','runtime_checkpoint_recovers_mixed_crash_states','runtime_checkpoint_persists_intent_before_load','runtime_checkpoint_consumes_intent_only_after_rehide','runtime_checkpoint_rejects_mismatched_resume','runtime_checkpoint_cleanup_is_idempotent_in_every_state','runtime_checkpoint_two_sessions_leave_no_stale_paths','runtime_dedicated_start_reaches_preparing_without_checkpoint')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 6 Dev tests must cover $Marker"
    }
    foreach ($Marker in @('runtime_actor_rejects_nil_inventory_parent','runtime_actor_rejects_throwing_inventory_accessors')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 6 actor ownership tests must cover $Marker"
    }
    foreach ($Marker in @('runtime_checkpoint_load_wait_is_bounded_and_wrap_safe','runtime_checkpoint_transient_mutation_failures_retry_to_success','runtime_checkpoint_permanent_mutation_throws_time_out')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 6 bounded checkpoint tests must cover $Marker"
    }
    Assert-True ($Task5DevTestContent -match 'runtime_checkpoint_zero_required_target_waits_for_timeout') 'Task 6 checkpoint tests must cover a source-absent zero-byte required target'
    Assert-True ($Task5DevTestContent -match 'runtime_pre_session_fatal_waits_for_cleanup_before_disconnect') 'Fatal cleanup tests must cover failures before ArenaSession assignment'
    Assert-True ($Task5DevTestContent -match 'runtime_prepare_resume_legacy_mismatch_is_normalized') 'Resume routing tests must normalize legacy store mismatch codes'
    foreach ($Marker in @('runtime_checkpoint_late_dds_retries_throw_then_succeeds','runtime_checkpoint_late_dds_permanent_failures_are_bounded_and_wrap_safe','runtime_bootstrap_teardown_drains_transient_exact_cleanup_idempotently','runtime_bootstrap_teardown_resets_across_sessions','runtime_completed_teardown_allows_next_loaded_launch_activation','runtime_bootstrap_teardown_permanent_failures_are_bounded','runtime_bootstrap_teardown_rejects_unbounded_update_limits','runtime_bootstrap_teardown_override_budgets_route_exactly','runtime_failed_teardown_retries_then_latches_success')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 6 final lifecycle hardening tests must cover $Marker"
    }
    foreach ($Marker in @('runtime_checkpoint_fresh_process_recovers_all_exact_layouts','runtime_checkpoint_fresh_recovery_rejects_missing_inconsistent_and_mismatch','runtime_checkpoint_fresh_recovery_rejects_persisted_intent_drift')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 6 fresh-process recovery tests must cover $Marker"
    }
    Assert-True ($Task5DevTestContent -match 'runtime_fatal_recovery_waits_for_cleanup_before_disconnect') 'Fatal recovery tests must gate disconnect on exact cleanup'
    Assert-True ($Task5DevTestContent -match 'runtime_engine_checkpoint_port_uses_xray_alias_for_existence') 'Checkpoint tests must reproduce the installed X-Ray alias-plus-name existence signature'
    Assert-True ($Task5DevTestContent -match 'runtime_dedicated_start_reaches_preparing_without_checkpoint') 'Runtime tests must prove dedicated startup reaches preparation without checkpoint IO'
}

$Task7EntityPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
Assert-True (Test-Path -LiteralPath $Task7EntityPath) 'Task 7 entity adapter is missing'
if (Test-Path -LiteralPath $Task5CompatPath) {
    foreach ($Marker in @('alife().get_children','alife().object','alife().set_switch_online','alife().set_switch_offline','se_load_var','level.object_by_id','game_object.friend','game_object.enemy','system_ini.r_u32','GA_AMMO_BOX_SIZE_INVALID')) {
        Assert-True ($Task5CompatContent -match [regex]::Escape($Marker)) "Task 7 compatibility preflight must cover $Marker"
    }
}
if (Test-Path -LiteralPath $Task7EntityPath) {
    $Task7EntityContent = Get-Content -LiteralPath $Task7EntityPath -Raw
    foreach ($Marker in @('begin_apply','update','on_npc_death','living_opponent_count','neutralize_owned_opponents','death_neutralized','clear_enemy','GA_ENTITY_DEATH_NEUTRALIZE_FAILED','cleanup','registry_snapshot','gamma_arena_owner','se_load_var','get_children','parent_id','safe_release_manager','set_relation','game_object.enemy','game_object.friend','-5000','AI_STL_S','arena_enemy','persist_death_dropped','GA_ENTITY_DEATH_DROPPED_VERIFY_FAILED','hold_offline','request_online','online_requested','held_offline','staged_friendly','set_actor_hold','GA_ENTITY_ACTIVATION_HOLD_FAILED','GA_ENTITY_ONLINE_REQUEST_FAILED','GA_ENTITY_ONLINE_TIMEOUT','GA_ENTITY_RELEASE_TIMEOUT','GA_ENTITY_PARENT_RELEASE_BLOCKED','GA_ENTITY_CHILD_PARENT_UNPROVEN','register_and_tag_created_item','profile_runtime','gamma_arena_item_materializer.descriptors','actor_spec.items')) {
        Assert-True ($Task7EntityContent -match [regex]::Escape($Marker)) "Task 7 entity adapter must cover $Marker"
    }
    Assert-True ($Task7EntityContent -match 'type\([^\r\n]*\)\s*==\s*"function"') 'Task 7 child snapshots must support the real GAMMA iterator contract'
    Assert-True ($Task7EntityContent -match 'function\s+EntityAdapter:register_and_tag_created_item[\s\S]{0,1200}self:register_record[\s\S]{0,800}self:tag_record') 'Every valid returned item id must be registered and tagged before later return values are inspected'
    Assert-True ($Task7EntityContent -match 'function\s+EntityAdapter:create_descriptor[\s\S]{0,1800}for\s+index,\s*entity\s+in\s+ipairs\(entities\)\s+do[\s\S]{0,400}self:register_and_tag_created_item') 'Multi-return item creation must authorize each entity inside the validation loop'
    Assert-True ($Task7EntityContent -match 'if\s+entity\.value\s*==\s*nil\s+then[\s\S]{0,900}record_by_id[\s\S]{0,900}GA_ENTITY_CHILD_PARENT_UNPROVEN') 'Missing child re-reads may retire only a proved registered Arena child and must otherwise block parent release'
    Assert-True ($Task7EntityContent -match 'if\s+parent_id\s*==\s*nil\s+then[\s\S]{0,500}GA_ENTITY_CHILD_PARENT_UNPROVEN') 'Unreadable authoritative child parents must block parent release'
    Assert-True ($Task7EntityContent -notmatch '\balife_release_id\s*\(') 'Entity adapter must never directly release a standalone stalker'
    Assert-True ($Task7EntityContent -notmatch '\bmath\.(random|randomseed)\b') 'Entity adapter must not consume global randomness'
    Assert-True ($Task7EntityContent -match 'function\s+EntityAdapter:on_npc_death[\s\S]{0,900}if\s+not\s+owner\.ok\s+then\s+return\s+owner\s+end') 'Registered death owner-tag read failures must propagate instead of looking like benign mismatches'
    $Task5NeutralizeBlock = [regex]::Match($Task7EntityContent, 'function\s+EntityAdapter:neutralize_owned_opponents[\s\S]*?function\s+EntityAdapter:clock').Value
    Assert-True ($Task5NeutralizeBlock -match 'self\.registry\.npcs[\s\S]{0,700}self:load_owner_tag[\s\S]{0,900}self\.deps\.online_object') 'Death neutralization must remain registry-, persisted-owner-, and online-object-bounded'
    Assert-True ($Task5NeutralizeBlock -notmatch 'level\.object_by_id|alife\(\)\.object|for\s+[^\r\n]+\s+in\s+pairs\s*\(\s*db') 'Death neutralization must never fall back to a global NPC scan'
    Assert-True ($Task7EntityContent -match 'expected_created_quantity') 'Opponent loadout must derive exact ammo allocation when server quantity is unavailable'
    Assert-True ($Task7EntityContent -match 'role\s*=\s*descriptor\.category') 'Opponent universal items must preserve materializer categories on owned descriptors'
    Assert-True ($Task7EntityContent -match 'community\s*=\s*participant\.community') 'Entity adapter participant copies must preserve dynamic FightSpec community'
    Assert-True ($Task7EntityContent -notmatch 'copy_participant\(participant,\s*index\)') 'Entity adapter must not replace validated logical opponent slots with dense array indexes.'
    Assert-True ($Task7EntityContent -match 'copy_participant\(participant,\s*participant\.slot\)') 'Entity adapter must copy each validated logical opponent slot.'
    Assert-True ($Task7EntityContent -match 'self\.opponent_by_slot\s*=\s*opponent_by_slot') 'Entity adapter must retain a logical-slot lookup map alongside dense spawn order.'
    Assert-True ($Task7EntityContent -match 'self\.opponent_by_slot\[record\.slot\]') 'Entity runtime lookups must address opponents by validated logical slot.'
    Assert-True ($Task7EntityContent -notmatch 'ensure_weapon_equipped|GA_ENTITY_EQUIP_TIMEOUT') 'NPC activation must not wait for a weapon to become active before hostility starts combat AI'
    $MedicalActivationBlock = [regex]::Match($Task7EntityContent, 'function\s+EntityAdapter:drive_online[\s\S]*?function\s+EntityAdapter:add_cleanup_error').Value
    Assert-True ($MedicalActivationBlock.IndexOf('hidden_charge_cleared') -ge 0 -and $MedicalActivationBlock.IndexOf('clear_hidden_charge') -lt $MedicalActivationBlock.IndexOf('set_actor_hostile')) 'Entity activation must clear stock hidden healing before combat hostility'
    Assert-True ($Task7EntityContent -match 'function\s+EntityAdapter:consume_medical_item\s*\(') 'Entity adapter must expose guarded physical medicine consumption'
    foreach ($Marker in @('GA_ENTITY_MEDICAL_FIGHT_STALE','release_reason','consumed','current_fight_id')) {
        Assert-True ($Task7EntityContent -match [regex]::Escape($Marker)) "Physical medicine consumption must cover $Marker"
    }
    $MedicalConsumptionBlock = [regex]::Match($Task7EntityContent, 'function\s+EntityAdapter:consume_medical_item[\s\S]*?function\s+EntityAdapter:warn_wound_query_once').Value
    Assert-True ($MedicalConsumptionBlock -match 'candidate\.source\s*==\s*"assigned"[\s\S]*candidate\.parent_id\s*==\s*npc_id[\s\S]*candidate\.section\s*==\s*section') 'Physical medicine consumption must select an assigned registered item for the requested NPC and section.'
    Assert-True ($MedicalConsumptionBlock -match 'parent_id\s*~=\s*npc_id[\s\S]*actual_section\.value\s*~=\s*section[\s\S]*item_owner\.value\s*~=\s*self\.session_id\s+or\s+record\.tagged\s*~=\s*true[\s\S]*self\.deps\.release') 'Physical medicine consumption must prove registry, live parent/section, and persisted owner before release.'
    }

$Task7ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_fight_validator_v9.script'
if (Test-Path -LiteralPath $Task7ValidatorPath) {
    $Task7ValidatorContent = Get-Content -LiteralPath $Task7ValidatorPath -Raw
    foreach ($Marker in @('effective_profile','validate_runtime_profile','AI_STL_S','arena_enemy','GA_FIGHTSPEC_PROFILE_RUNTIME_INVALID')) {
        Assert-True ($Task7ValidatorContent -match [regex]::Escape($Marker)) "Task 7 validator must cover $Marker"
    }
    Assert-True ($Task7ValidatorContent -match 'profile\.runtime_community') 'Fight validation must verify the effective NPC profile against runtime community rather than source faction'
    foreach ($Pattern in @('catalog\.schema_version\s*~=\s*10', 'catalog\.revision\s*~=\s*11', 'catalog\.generator_version\s*~=\s*11', 'ga-catalog-v10-')) {
        Assert-True ($Task7ValidatorContent -match $Pattern) "Task 4 strict validator must enforce catalog identity: $Pattern"
    }
}
$Task7FightSpecTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_fight_spec.script'
if (Test-Path -LiteralPath $Task7FightSpecTestPath) {
    $Task7FightSpecTestContent = Get-Content -LiteralPath $Task7FightSpecTestPath -Raw
    $LogicalSlotCase = 'validator_to_entity_adapter_preserves_nonsequential_logical_slot'
    $LogicalSlotRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($LogicalSlotCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($LogicalSlotCase) + '\s*\}'
    Assert-True (([regex]::Matches($Task7FightSpecTestContent, $LogicalSlotRegistration)).Count -eq 1) "Regression case must be registered exactly: $LogicalSlotCase -> $LogicalSlotCase."
    $LogicalSlotBody = [regex]::Match($Task7FightSpecTestContent, 'local\s+function\s+' + [regex]::Escape($LogicalSlotCase) + '\(\)[\s\S]*?\r?\nend').Value
    Assert-True ($LogicalSlotBody -match 'opponents\[1\]\.slot\s*=\s*2' -and
        $LogicalSlotBody -match 'gamma_arena_fight_validator_v9\.validate' -and
        $LogicalSlotBody -match 'gamma_arena_entity_adapter\.new' -and
        $LogicalSlotBody -match 'begin_apply' -and
        $LogicalSlotBody -match 'opponents\[1\]\.slot\s*,\s*2' -and
        $LogicalSlotBody -match 'opponent_by_slot\[2\]') 'Validator-to-entity regression must prove logical slot 2 survives the adapter boundary and is addressable by slot.'
}

$Task7FixturePath = Join-Path $RepoRoot 'tests\fixtures\effective-arena-npcs-v1.ini'
Assert-True (Test-Path -LiteralPath $Task7FixturePath) 'Task 7 effective NPC fixture is missing'
if (Test-Path -LiteralPath $Task7FixturePath) {
    $Task7FixtureContent = Get-Content -LiteralPath $Task7FixturePath -Raw
    Assert-True (([regex]::Matches($Task7FixtureContent, '(?m)^section\s*=\s*gamma_arena_bandit_(novice|trainee|experienced|veteran)\s*$')).Count -eq 4) 'Effective NPC fixture must contain exactly four Arena sections'
    Assert-True (([regex]::Matches($Task7FixtureContent, '(?m)^class\s*=\s*AI_STL_S\s*$')).Count -eq 4) 'Every effective Arena NPC must resolve to AI_STL_S'
    Assert-True (([regex]::Matches($Task7FixtureContent, '(?m)^community\s*=\s*arena_enemy\s*$')).Count -eq 4) 'Every effective Arena NPC must resolve to the isolated arena_enemy runtime community'
    Assert-True ($Task7FixtureContent -notmatch '(?m)^death_dropped\s*=') 'Effective-profile fixture must not pretend the runtime death-manager save-var is an LTX property'
}

$Task7NpcPath = Join-Path $RepoRoot 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx'
if (Test-Path -LiteralPath $Task7NpcPath) {
    $Task7NpcContent = Get-Content -LiteralPath $Task7NpcPath -Raw
    Assert-True ($Task7NpcContent -notmatch '(?m)^death_dropped\s*=') 'Arena NPC LTX must not treat death_dropped as an inert section property'
    $Task7NpcSections = [regex]::Matches($Task7NpcContent, '(?ms)^\[(?<name>gamma_arena_[^\]]+)\][^\r\n]*\r?\n(?<body>.*?)(?=^\[|\z)')
    Assert-True ($Task7NpcSections.Count -gt 0) 'Arena NPC LTX must expose at least one owned profile alias'
    foreach ($Section in $Task7NpcSections) {
        Assert-True ($Section.Groups['body'].Value -match '(?m)^community\s*=\s*arena_enemy\s*$') "Arena NPC alias $($Section.Groups['name'].Value) must explicitly override runtime community to arena_enemy"
    }
}

if (Test-Path -LiteralPath $Task7EntityPath) {
    Assert-True ($Task7EntityContent -match 'ARENA_RUNTIME_COMMUNITY\s*=\s*"arena_enemy"') 'Entity adapter must define the isolated Arena runtime community'
    Assert-True ($Task7EntityContent -match 'validate_effective_profile\([^\r\n]+ARENA_RUNTIME_COMMUNITY') 'Entity pre-spawn validation must require the isolated runtime community'
    Assert-True ($Task7EntityContent -match 'function\s+EntityAdapter:activate_ready') 'Entity adapter must split fully staged READY from hostile activation'
    Assert-True ($Task7EntityContent -match 'function\s+EntityAdapter:activate_ready[\s\S]{0,700}verify_item_ownership[\s\S]{0,3000}set_actor_hostile') 'READY activation must revalidate assigned item ownership before applying hostility'
    Assert-True ($Task7EntityContent -match 'WAIT_ACTOR_LOADOUT[\s\S]{0,700}set_state\("SPAWNING"\)') 'Actor loadout readiness must start spawning before countdown'
    Assert-True ($Task7EntityContent -match 'self\.state_value\s*==\s*"READY"[\s\S]{0,350}opponent_gate_open') 'Closed activation gate must hold a fully staged READY transaction'
    Assert-True ($Task7EntityContent -notmatch 'set_state\("COUNTDOWN"\)') 'Entity adapter must not own the visible countdown state'
}

$Task7CatalogPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script'
$Task7CompatPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script'
if (Test-Path -LiteralPath $Task7CatalogPath) {
    $Task7CatalogContent = Get-Content -LiteralPath $Task7CatalogPath -Raw
    Assert-True ($Task7CatalogContent -match 'profile\.community\s*=\s*faction') 'Arena catalog must retain the source faction as profile.community'
    Assert-True ($Task7CatalogContent -match 'profile\.runtime_community\s*=\s*ARENA_RUNTIME_COMMUNITY') 'Arena catalog must expose a separate fixed runtime community'
    Assert-True ($Task7CatalogContent -match 'ARENA_RUNTIME_COMMUNITY\s*=\s*"arena_enemy"') 'Arena catalog runtime community must be exactly arena_enemy'
}
if (Test-Path -LiteralPath $Task7CompatPath) {
    $Task7CompatContent = Get-Content -LiteralPath $Task7CompatPath -Raw
    Assert-True ($Task7CompatContent -match 'profile\.runtime_community') 'Compatibility preflight must consume the profile runtime community separately from its source faction'
}

if (Test-Path -LiteralPath $Task5BootstrapPath) {
    foreach ($Marker in @('gamma_arena_entity_adapter.new','se_load_var','se_save_var(id, nil, "death_dropped", value)','force_set_goodwill','game_object.enemy','game_object.friend','step_entity_cleanup','step_actor_cleanup','last_update_at','pending = true','entity_teardown_max_updates','actor_teardown_max_updates','MAX_TEARDOWN_UPDATES','new_actor_loadout_port','new_runtime_entity_exists_port','GA_ACTOR_LOADOUT_OWNERSHIP_PROOF_INVALID','entity_exists','hold_entity_offline','request_entity_online','set_switch_online','set_switch_offline','switch_online','level.object_by_id','apply_actor_activation_hold','set_enemy','apply_actor_hostility','effective_ammo_box_size','system.r_u32','ammo_box_size','box_size')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Task 7 bootstrap composition must cover $Marker"
    }
    Assert-True ($Task5BootstrapContent -notmatch 'relation_registry\.set_goodwill') 'Task 7 must not require the nonexistent installed-GAMMA relation_registry.set_goodwill API'
    Assert-True ($Task5BootstrapContent -notmatch 'function\s+drain_entity_cleanup') 'Task 7 entity cleanup must be frame-driven rather than a same-callback drain loop'
    Assert-True ($Task5BootstrapContent -match 'Current actor item parent proof is malformed[\s\S]{0,1200}Current actor item section proof is malformed') 'Actor cleanup must reject malformed current-object ownership proofs before release'
    Assert-True ($Task5BootstrapContent -match 'alife_create_item\(section,\s*parent,\s*\{\s*ammo\s*=\s*count\s*\}\)') 'Task 7 must pass exact ammo rounds through the GAMMA alife_create_item property table'
    Assert-True ($Task5BootstrapContent -match 'return\s+alife_create_item\(section,\s*parent\)') 'Task 7 must create ordinary inventory items without a numeric third argument'
    Assert-True ($Task5BootstrapContent -match 'expected_created_quantity') 'Actor loadout must derive exact ammo allocation when server quantity is unavailable'
    Assert-True ($Task5BootstrapContent -match 'role\s*=\s*"grenade"') 'Actor loadouts must materialize FightSpec grenades as ordinary owned descriptors'
    Assert-True ($Task5BootstrapContent -notmatch 'can_throw_grenades') 'Runtime must not force native grenade throwing behavior'
    Assert-True ($Task5BootstrapContent -match 'local\s+function\s+entity_ammo_quantity[\s\S]{0,900}return\s+nil\s*[\r\n]+end') 'NPC production quantity port must expose unavailable server ammo quantity as nil for exact box-size derivation'
    Assert-True ($Task5BootstrapContent -notmatch 'Ammo server entity does not expose its exact round count') 'NPC production quantity port must not turn unavailable server binding metadata into a fatal Result'
    Assert-True ($Task5BootstrapContent -notmatch 'ensure_entity_weapon_equipped|GA_ENTITY_EQUIP_TIMEOUT') 'Bootstrap must leave NPC weapon selection to combat AI after validated inventory ownership'
    foreach ($Marker in @('gamma_arena_npc_medical.new','healing_charge','change_health','cap_bleeding','npc_medical_ini')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Bootstrap NPC medical composition must cover $Marker"
    }
    $Task11HostilityBlock = [regex]::Match($Task5BootstrapContent, 'function\s+apply_actor_hostility[\s\S]*?local\s+function\s+apply_actor_activation_hold').Value
    Assert-True ($Task11HostilityBlock -match 'set_relation[\s\S]*force_set_goodwill') 'Hostile activation must apply relation then goodwill'
    Assert-True ($Task11HostilityBlock -notmatch 'make_object_visible_somewhen|set_enemy') 'Hostile activation must not seed omniscient memory or force a current target'
    Assert-True ($Task5BootstrapContent -notmatch 'ports\.reserve_magazines|reserve_magazines\s*=') 'Runtime must not regenerate the actor reserve-magazine floor'
    foreach ($Marker in @('gamma_arena_mags_redux.new','mags_redux_resolve_api','mags_redux_magazine_capacity','rawget(_G, "magazine_binder")','rawget(_G, "mags_patches")','is_supported_weapon','weapon_default_magazine','get_mag_loaded','is_carried_mag','fill_mag','max_mag_size','bonus_descriptors','initialize_created','GA_MAGS_REDUX_RESERVE_READY')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Mags Redux production binding must cover $Marker"
    }
    Assert-True ($Task5BootstrapContent -notmatch 'function\s+mags_patches\.|function\s+magazine_binder\.') 'Gamma Arena must not override Mags Redux vendor functions'
    Assert-True ($Task5BootstrapContent -match 'initialize_created\s*=\s*function\s*\([^,]+,\s*record,\s*descriptor\)[\s\S]{0,500}mags_redux:initialize\(record\.id') 'Mags Redux initialization must use the registered Arena ownership record id'
    Assert-True ($Task5BootstrapContent -match 'function\s+engine_inventory_slot\(ltx_slot\)[\s\S]{0,700}ltx_slot\s*\+\s*1') 'Actor loadout must translate zero-based LTX slots to one-based Lua inventory API slots'
    foreach ($Marker in @('WAIT_SLOT_VERIFY','CHARGE_OUTFIT','WAIT_MAGAZINE_VERIFY','WAIT_ACTIVE_VERIFY','outfit_requires_power','exo_is_object','exo_get_data','exo_init_data','exo_set_data')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Actor equipment must retain cross-frame phase $Marker"
    }
    foreach ($Marker in @('WAIT_ACTOR_LOADOUT','move_to_slot','item_in_slot','set_ammo_elapsed','get_ammo_in_magazine','ammo_mag_size','update_loadout','GA_ACTOR_LOADOUT_EQUIP_TIMEOUT')) {
        Assert-True (($Task5BootstrapContent + $Task7EntityContent + $Task6ActorContent) -match [regex]::Escape($Marker)) "Equipped actor loadout must cover $Marker"
    }
    foreach ($Marker in @('runtime_actor_loadout_derives_unreadable_server_ammo_quantity','runtime_entity_derives_unreadable_server_ammo_quantity','runtime_actor_loadout_translates_ltx_slots_to_lua_slots','runtime_actor_loadout_progress_survives_clock_stalls','runtime_actor_loadout_no_progress_timeout_has_context','new_actor_loadout_test_fixture','runtime_actor_loadout_charges_powered_exo_before_ready','runtime_actor_loadout_charges_proto_outfit_without_repair_type','runtime_actor_loadout_ordinary_outfit_bypasses_exo_charge','runtime_actor_loadout_exo_charge_failures_rollback')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Runtime ammo allocation regression must cover $Marker"
    }
    Assert-True ($Task5DevTestContent -match [regex]::Escape('runtime_bootstrap_missing_outfit_repair_type_is_ordinary')) 'Runtime actor loadout must cover missing ordinary outfit repair_type'
    Assert-True ($Task5BootstrapContent -match 'if\s+present_ok\s+and\s+present\s+==\s+false\s+then\s+return\s+gamma_arena_result\.ok\(false\)\s+end') 'Missing effective outfit repair_type must classify as ordinary rather than fail the loadout transaction'
    Assert-True ($Task5BootstrapContent -match 'function\s+effective_outfit_requires_power[\s\S]{0,500}string\.find\(section,\s*"proto",\s*1,\s*true\)[\s\S]{0,200}return\s+gamma_arena_result\.ok\(true\)') 'Runtime exo classification must preserve the installed Powered Exos proto rule'
    foreach ($Marker in @('last_progress_at','elapsed_since_progress_ms','total_elapsed_ms')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Actor equipment inactivity timeout must expose $Marker"
    }
    Assert-True ($Task5DevTestContent -match [regex]::Escape('runtime_result_modal_releases_global_input')) 'Runtime result modal must prove global input ownership is released'
}

if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    foreach ($Marker in @('entities','on_npc_death','living_opponent_count','GA_ENTITY_COUNT_UNAVAILABLE','GA_ENTITY_COUNT_STATE_INVALID')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Task 7 orchestration integration must cover $Marker"
    }
    $InactiveCleanupPoll = [regex]::Match($Task5OrchestratorContent, 'if\s+not\s+self:is_active\(\)\s+and\s+self\.cleanup_required\s+then[\s\S]{0,700}?return\s+self:drive_runtime\(\)').Value
    Assert-True ($InactiveCleanupPoll.Length -gt 0) 'Inactive cleanup polling must not bypass launch/resume activation while awaiting_activation is set'
    Assert-True ($InactiveCleanupPoll -match 'begin_update') 'Inactive cleanup polling must advance actor absence proofs on the later engine update'
    Assert-True ($Task5OrchestratorContent -match 'if\s+self\.cleanup_required\s+then[\s\S]{0,500}self:cleanup_ready_for_disconnect\(\)') 'A later loaded Arena must consume exact cleanup readiness before launch/resume activation'
    $Task7LaunchBlock = [regex]::Match($Task5OrchestratorContent, 'function\s+Orchestrator:activate_once[\s\S]*?function\s+Orchestrator:layout_snapshot').Value
    $Task7PreflightIndex = $Task7LaunchBlock.IndexOf('preflight_fight')
    $Task7NormalizeIndex = $Task7LaunchBlock.IndexOf('set_runtime_stage("NORMALIZING")')
    Assert-True ($Task7PreflightIndex -ge 0 -and $Task7NormalizeIndex -gt $Task7PreflightIndex) 'FightSpec preflight and immutable cache must precede the mutating actor normalization stage.'
    $Task7PrepareBlock = [regex]::Match($Task5OrchestratorContent, 'function\s+Orchestrator:prepare_fight[\s\S]*?function\s+Orchestrator:begin_countdown_after_equipment').Value
    Assert-True ($Task7PrepareBlock -match 'begin_apply') 'Entity application must remain in post-normalization FightSpec preparation.'
    $Task7ContinuationBlock = [regex]::Match($Task5OrchestratorContent, 'function\s+Orchestrator:drive_continuation[\s\S]*?function\s+Orchestrator:drive_runtime').Value
    $Task7ContinuationPreflightIndex = $Task7ContinuationBlock.IndexOf('preflight_fight')
    $Task7ContinuationResetIndex = $Task7ContinuationBlock.IndexOf('reset_for_rematch')
    Assert-True ($Task7ContinuationPreflightIndex -ge 0 -and $Task7ContinuationResetIndex -gt $Task7ContinuationPreflightIndex) 'Victory continuation must preflight the next immutable FightSpec before mutating actor reset.'
}

if (Test-Path -LiteralPath $Task5DevTestPath) {
    foreach ($Marker in @('runtime_preflight_requires_task7_entity_ports_and_ammo_metadata','runtime_entity_actor_loadout_precedes_spawn','runtime_entity_npcs_are_offline_until_atomic_activation','runtime_entity_online_wait_is_bounded_and_wrap_safe','runtime_entity_active_defers_input_release_to_task8','runtime_bootstrap_actor_loadout_port_is_bound_and_exact','runtime_actor_loadout_creates_physical_grenades_and_rolls_back','runtime_actor_loadout_rollback_blocks_disconnect_until_absent','runtime_actor_loadout_malformed_existence_blocks_teardown_disconnect','runtime_bootstrap_actor_existence_lookup_fails_closed','runtime_bootstrap_hostility_port_is_feature_probed','runtime_entity_ammo_box_size_failure_precedes_actor_mutation','runtime_entity_partial_failures_rollback_in_reverse','runtime_entity_creates_physical_grenade_and_rolls_back_failure','runtime_entity_purges_only_snapshot_children_still_parented','runtime_entity_supports_real_get_children_iterator','runtime_entity_multi_return_ammo_is_exact','runtime_entity_death_dropped_is_persisted_and_round_tripped','runtime_entity_multi_return_late_failure_is_fully_registered','runtime_entity_multi_return_invalid_or_duplicate_id_rolls_back_every_owned_creation','runtime_entity_registry_is_plain_ids_only','runtime_entity_cleanup_requires_registry_and_tag','runtime_entity_forged_tag_is_ignored','runtime_entity_tag_loss_fails_safe','runtime_entity_cleanup_adopts_unloaded_weapon_child','runtime_entity_cleanup_adopts_late_child_before_parent','runtime_entity_runtime_child_tag_failure_is_terminal','runtime_entity_runtime_child_limit_is_terminal','runtime_entity_parent_release_blocks_unreadable_child_parent','runtime_entity_cleanup_is_idempotent','runtime_entity_lifecycle_cleanup_takes_over_mid_rollback','runtime_entity_existence_result_must_be_boolean','runtime_entity_duplicate_death_is_idempotent','runtime_entity_unregistered_death_is_ignored','runtime_entity_object_death_signature_is_normalized','runtime_entity_numeric_death_requires_test_injection','runtime_registered_death_owner_tag_failures_route_through_real_callback_router','runtime_registered_death_mismatching_owner_tag_is_benign','runtime_entity_release_is_async_and_never_direct','runtime_entity_release_timeout_is_wrap_safe','runtime_entity_max_cardinality_cleanup_fits_default_budget','runtime_entity_relations_friend_first_then_actor_hostile','runtime_entity_activation_does_not_wait_for_precombat_active_item','runtime_entity_callbacks_fail_closed','runtime_validator_rejects_effective_nonhuman_profile','runtime_entity_runtime_profile_check_precedes_actor_mutation','runtime_orchestrator_living_count_fails_closed','runtime_entity_actor_loadout_readiness_starts_spawning_without_gate')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 7 Dev tests must cover $Marker"
    }
    foreach ($Marker in @('runtime_fightspec_preflight_failure_precedes_actor_normalization','runtime_fightspec_preflight_caches_before_normalization_and_applies_after_purge')) {
        $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Marker) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Marker) + '\s*\}'
        Assert-True (([regex]::Matches($Task5DevTestContent, $Registration)).Count -eq 1) "FightSpec lifecycle case must be registered exactly: $Marker -> $Marker"
    }
    $Task7ContinuationRegistration = '\{\s*name\s*=\s*"runtime_victory_continuation_preflights_before_actor_reset"\s*,\s*fn\s*=\s*runtime_victory_continuation_preflights_before_actor_reset\s*\}'
    Assert-True (([regex]::Matches($Task5DevTestContent, $Task7ContinuationRegistration)).Count -eq 1) 'FightSpec continuation lifecycle case must be registered exactly.'
    foreach ($Marker in @('runtime_entity_consumes_owned_medical_item_once','runtime_entity_medical_consumption_rejects_stale_foreign_and_absent_items')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Physical medicine Dev tests must cover $Marker"
    }
    foreach ($Marker in @('runtime_preflight_rejects_npc_medical_ai_conflict','runtime_npc_medical_prioritizes_health_and_applies_thirteen_bounded_pulses','runtime_npc_medical_bandage_threshold_and_cancellation_are_fail_closed','runtime_npc_medical_lifecycle_is_active_only')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "NPC medical Dev tests must cover $Marker"
    }
}

$MedicalGeneratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_medical_generator.script'
if (Test-Path -LiteralPath $MedicalGeneratorPath) {
    $MedicalGeneratorContent = Get-Content -LiteralPath $MedicalGeneratorPath -Raw
    Assert-True ($MedicalGeneratorContent -match 'local\s+category_is_required\s*=\s*item\.category\s*==\s*"health"\s+or\s+item\.category\s*==\s*"rare"[\s\S]{0,500}\(not\s+required\s+or\s+category_is_required\)') 'Actor medical generation must require a health/rare healer before optional picks.'
}

$NpcMedicalPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_npc_medical.script'
if (Test-Path -LiteralPath $NpcMedicalPath) {
    $NpcMedicalContent = Get-Content -LiteralPath $NpcMedicalPath -Raw
    foreach ($Marker in @('RECONCILE_INTERVAL_MS = 250','MEDICAL_EPOCH = 1','HEALTH_THRESHOLD = 0.60','BLEEDING_THRESHOLD = 0.15','MEDKIT_PULSES = 13','MEDKIT_HEALTH_PER_PULSE = 0.05','MEDKIT_BLEEDING_CAP = 0.01','BANDAGE_BLEEDING_CAP = 0.07','action_ordinal','GA_NPC_MEDICAL_SCHEDULED','GA_NPC_MEDICAL_CONSUMED','GA_NPC_MEDICAL_CANCELLED','GA_NPC_MEDICAL_COMPLETED')) {
        Assert-True ($NpcMedicalContent -match [regex]::Escape($Marker)) "NPC medical state machine must contain $Marker"
    }
    Assert-True ($NpcMedicalContent -notmatch '\bmath\.(random|randomseed)\b') 'NPC medical state machine must not use global randomness'
}

$Task3DataFiles = @(
    'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx',
    'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx',
    'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx',
    'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx',
    'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx',
    'schemas\fight-spec-v9.md',
    'tests\fixtures\golden-fights-v9.txt'
)
foreach ($RelativePath in $Task3DataFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)) "Task 4 current data contract is missing: $RelativePath"
}

$CatalogPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$DifficultyPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$LayoutPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
$NpcPath = Join-Path $RepoRoot 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx'
$SkipPath = Join-Path $RepoRoot 'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx'
if (Test-Path -LiteralPath $CatalogPath) {
    $CatalogContent = Get-Content -LiteralPath $CatalogPath -Raw
    Assert-True ($CatalogContent -match '(?m)^schema_version\s*=\s*10\s*$') 'Catalog must declare schema_version = 10'
    Assert-True ($CatalogContent -match '(?m)^revision\s*=\s*11\s*$') 'Catalog must declare revision = 11'
    Assert-True ($CatalogContent -match '(?m)^generator_version\s*=\s*11\s*$') 'Catalog must declare generator_version = 11'
    Assert-True (([regex]::Matches($CatalogContent, '(?m)^section\s*=\s*wpn_knife[2-9]?\s*$')).Count -eq 9) 'Knife catalog must contain exactly the nine installed GAMMA knife sections'
    Assert-True ($CatalogContent -match '(?ms)^\[outfit_novice\]\s+section\s*=\s*novice_outfit\s+cost\s*=\s*1\s+armor_class\s*=\s*light\s*$') 'Novice outfit must declare the light armor class'
    Assert-True ($CatalogContent -match '(?ms)^\[outfit_stalker\]\s+section\s*=\s*stalker_outfit\s+cost\s*=\s*3\s+armor_class\s*=\s*medium\s*$') 'Stalker outfit must declare the medium armor class'
    Assert-True ($CatalogContent -match '(?ms)^\[outfit_banditmerc\]\s+section\s*=\s*banditmerc_outfit\s+cost\s*=\s*4\s+armor_class\s*=\s*scientific\s*$') 'Banditmerc outfit must declare the scientific armor class'
    foreach ($Profile in @('gamma_arena_bandit_novice', 'gamma_arena_bandit_trainee', 'gamma_arena_bandit_experienced', 'gamma_arena_bandit_veteran')) {
        Assert-True ($CatalogContent -match [regex]::Escape($Profile)) "Human profile catalog must include $Profile"
    }
    Assert-True ($CatalogContent -match '(?m)^\[medical_items\]\r?$') 'Catalog must declare the curated medical_items group'
    foreach ($Marker in @('section = rebirth','category = rare','actor_cost = 7','npc_cost = 2','max_count = 2')) {
        Assert-True ($CatalogContent.Contains($Marker)) "Medical catalog must declare $Marker"
    }
}
$Task3CatalogScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script'
if (Test-Path -LiteralPath $Task3CatalogScriptPath) {
    $Task3CatalogScriptContent = Get-Content -LiteralPath $Task3CatalogScriptPath -Raw
    Assert-True ($Task3CatalogScriptContent -match 'GA_DIFFICULTY_BUDGET_INFEASIBLE') 'Catalog loader must reject infeasible maximum-count budgets'
    Assert-True ($Task3CatalogScriptContent -match 'section_for_each') 'Runtime catalog enumeration must use section_for_each'
    Assert-True ($Task3CatalogScriptContent -match 'line_count') 'Runtime catalog enumeration must use line_count'
    Assert-True ($Task3CatalogScriptContent -match 'r_line') 'Runtime catalog enumeration must use r_line'
    Assert-True ($Task3CatalogScriptContent -match 'GA_CATALOG_SECTION_CHECK_FAILED') 'Catalog section checks must return structured errors'
    Assert-True ($Task3CatalogScriptContent -match 'GA_CATALOG_UNKNOWN_SECTION') 'Catalog loader must reject unknown sections'
    Assert-True ($Task3CatalogScriptContent -match 'GA_CATALOG_MANIFEST_INVALID') 'Catalog loader must enforce the exact v10 semantic manifest'
    Assert-True ($Task3CatalogScriptContent -match 'pcall\s*\(\s*load_impl') 'Catalog load boundary must convert arbitrary fixture failures to Result errors'
    Assert-True ($Task3CatalogScriptContent -match 'catalog_manifest_v10') 'Catalog loader must bind exact v10 catalog semantics'
    Assert-True ($Task3CatalogScriptContent -match 'difficulty_manifest_v5') 'Catalog loader must bind exact v5 difficulty semantics'
    Assert-True ($Task3CatalogScriptContent -match 'medical_skipped') 'Catalog loader must retain bounded diagnostics for missing optional medicine'
    foreach ($Diagnostic in @('Catalog group id count differs from v10', 'Catalog group contains a non-v10 id', 'Catalog group is missing a v10 id')) {
        Assert-True ($Task3CatalogScriptContent.Contains($Diagnostic)) "Strict catalog manifest diagnostic must identify v10: $Diagnostic"
    }
    foreach ($Marker in @('armor_class','player_weapon_weights','player_armor_weights','w_pistol','w_smg','w_shotgun','w_rifle','w_sniper','light','medium','scientific','heavy','powered_exo')) {
        Assert-True ($Task3CatalogScriptContent -match [regex]::Escape($Marker)) "Catalog loader must cover $Marker"
    }
    Assert-True ($Task3CatalogScriptContent -match 'layout_manifest_v2') 'Catalog loader must bind exact ordered v2 layout semantics'
    Assert-True ($Task3CatalogScriptContent -match 'gamma_arena_number\.is_integer') 'Catalog numeric parsing must use the finite integer contract'
    Assert-True ($Task3CatalogScriptContent -match 'ACTOR_WEAPON_QUARANTINE') 'Catalog must declare an explicit actor-only weapon quarantine.'
    Assert-True ($Task3CatalogScriptContent -match 'wpn_dtmdr\s*=\s*true') 'Actor quarantine must contain the exact confirmed wpn_dtmdr section.'
    Assert-True ($Task3CatalogScriptContent -match 'wpn_eft_mts_255_uh2\s*=\s*true') 'Actor quarantine must contain the exact confirmed wpn_eft_mts_255_uh2 section.'
    Assert-True ($Task3CatalogScriptContent -match 'actor_weapon_list') 'Catalog must expose a deterministic actor weapon list.'
    Assert-True ($Task3CatalogScriptContent -match 'actor_weapon_quarantine_v1') 'Catalog revision identity must include the actor quarantine policy.'
}
if (Test-Path -LiteralPath $DifficultyPath) {
    $DifficultyContent = Get-Content -LiteralPath $DifficultyPath -Raw
    foreach ($Difficulty in @('rookie', 'stalker', 'veteran', 'master')) {
        Assert-True ($DifficultyContent -match ("(?m)^\[ga_difficulty_" + $Difficulty + "\]\r?$")) "Difficulty catalog must include $Difficulty"
    }
    foreach ($Marker in @('tier = 4','player_gear_budget = 15','player_medical_budget = 8','medical_weight_rare = 10')) {
        Assert-True ($DifficultyContent.Contains($Marker)) "Difficulty medical contract must declare $Marker"
    }
}
if (Test-Path -LiteralPath $LayoutPath) {
    $LayoutContent = Get-Content -LiteralPath $LayoutPath -Raw
    Assert-True ($LayoutContent -match '(?m)^level\s*=\s*l05_bar\s*$') 'Layout must target l05_bar'
    Assert-True ($LayoutContent -match '(?m)^actor_spawn_path\s*=\s*t_way\s*$') 'Actor must spawn at the vanilla Rostok Arena ingress patrol'
    Assert-True ($LayoutContent -match '(?m)^actor_look_path\s*=\s*t_look\s*$') 'Actor must face the vanilla Rostok Arena ingress look patrol'
    Assert-True ($LayoutContent -notmatch '(?m)^actor_boundary_zone\s*=') 'Closed Rostok Arena must not declare a runtime boundary restrictor'
    Assert-True ($LayoutContent -match 'bar_arena_walk_3_1,bar_arena_walk_3_2,bar_arena_walk_6_1,bar_arena_walk_6_3,bar_arena_walk_6_6,bar_arena_walk_1_1') 'Layout must retain the vanilla six-human Arena patrol set'
    Assert-True ($LayoutContent -notmatch 'bar_arena_monstr_walk') 'Human Arena layouts must never assign the monster patrol'
    foreach ($Marker in @('virtual_capacity = 10','virtual_radii = 1.5,2.5','max_height_delta = 1.0','min_opponent_separation = 1.75','min_actor_separation = 8.0','max_base_distance = 3.0')) {
        Assert-True ($LayoutContent.Contains($Marker)) "Layout v2 must declare $Marker"
    }
}
if (Test-Path -LiteralPath $NpcPath) {
    $NpcContent = Get-Content -LiteralPath $NpcPath -Raw
    $ProfileBases = @{ army='military'; bandit='bandit'; csky='csky'; dolg='duty'; ecolog='ecolog'; freedom='freedom'; killer='killer'; monolith='monolith'; stalker='stalker' }
    foreach ($Faction in @('army','bandit','csky','dolg','ecolog','freedom','killer','monolith','stalker')) {
        $RankNames = @('novice','trainee','experienced','veteran')
        for ($RankIndex = 0; $RankIndex -lt $RankNames.Count; $RankIndex++) {
            $Alias = "gamma_arena_${Faction}_$($RankNames[$RankIndex])"
            Assert-True ($NpcContent -match ("(?m)^\[" + [regex]::Escape($Alias) + "\]:sim_default_" + [regex]::Escape($ProfileBases[$Faction]) + "_" + $RankIndex + "\r?$")) "NPC profile must inherit its effective faction/rank section: $Alias"
        }
    }
}
if (Test-Path -LiteralPath $SkipPath) {
    $SkipContent = Get-Content -LiteralPath $SkipPath -Raw
    Assert-True ($SkipContent -match '(?m)^!\[skip_npcs\]\s*$') 'Loadout patch must use ![skip_npcs]'
    Assert-True (([regex]::Matches($SkipContent, '(?m)^gamma_arena_(army|bandit|csky|dolg|ecolog|freedom|killer|monolith|stalker)_(novice|trainee|experienced|veteran)\s*=\s*(army|bandit|csky|dolg|ecolog|freedom|killer|monolith|stalker)\s*$')).Count -eq 36) 'Loadout patch must add all 36 Arena human aliases to skip_npcs'
}
$Task5BootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
$Task5RuntimeContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
$UniversalDeviceLifecycleCase = 'runtime_universal_actor_items_shutdown_precedes_cleanup_and_rollback'
$UniversalDeviceLifecycleRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($UniversalDeviceLifecycleCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($UniversalDeviceLifecycleCase) + '\s*\}'
Assert-True (([regex]::Matches($Task5RuntimeContent, $UniversalDeviceLifecycleRegistration)).Count -eq 1) "Universal actor-device lifecycle case must be registered exactly: $UniversalDeviceLifecycleCase -> $UniversalDeviceLifecycleCase"
Assert-True ($Task5BootstrapContent -match '(?s)function\s+new_actor_item_port\(ports\).*?shutdown_device.*?ports\.release_item') 'Universal actor-item cleanup/rollback must shut down global actor-device state before owned release.'
Assert-True (([regex]::Matches($Task5BootstrapContent, 'shutdown_device\s*=\s*shutdown_actor_device')).Count -ge 2) 'Legacy and universal actor-item ports must share the production actor-device shutdown seam.'

$Task2RunnerPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runner.script'
$Task2LogPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_log.script'
$Task2RngPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_rng.script'
if (Test-Path -LiteralPath $Task2RunnerPath) {
    $Task2RunnerContent = Get-Content -LiteralPath $Task2RunnerPath -Raw
    Assert-True ($Task2RunnerContent -match '(?s)pcall\s*\(\s*function\s*\(\s*\)\s*return\s+gamma_arena_test_domain\.run\s*\(\s*run_case\s*\)\s*end\s*\)') 'Dev test runner must resolve and execute the domain suite inside pcall'
    Assert-True ($Task2RunnerContent -match 'dev_test_autorun') 'Dev suite autorun must be controlled by an explicit setting'
    Assert-True ($Task2RunnerContent -match 'r_value\s*\(\s*"gamma_arena"\s*,\s*"dev_test_autorun"\s*,\s*1\s*,\s*false\s*\)') 'Dev suite autorun must default to false'
    Assert-True ($Task2RunnerContent -match 'if\s+not\s+autorun_enabled\(\)\s+then\s+return\s+end') 'Normal interactive launches must skip the synthetic Dev suite'
}
$Task4DomainTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_domain.script'
if (Test-Path -LiteralPath $Task4DomainTestPath) {
    $Task4DomainTestContent = Get-Content -LiteralPath $Task4DomainTestPath -Raw
    Assert-True ($Task4DomainTestContent -match 'gamma_arena_test_migrations\.run\s*\(\s*run_case_fn\s*\)') 'Dev domain suite must execute Task 4 migration/session tests'
}
if (Test-Path -LiteralPath $Task2LogPath) {
    $Task2LogContent = Get-Content -LiteralPath $Task2LogPath -Raw
    Assert-True ($Task2LogContent -match 'local\s+function\s+canonical_key\s*\(') 'Logger must define a canonical scalar context key function'
    Assert-True ($Task2LogContent -match 'key_type\s*==\s*"string"') 'Logger must canonicalize string keys'
    Assert-True ($Task2LogContent -match 'key_type\s*==\s*"number"') 'Logger must canonicalize number keys'
    Assert-True ($Task2LogContent -match 'key_type\s*==\s*"boolean"') 'Logger must canonicalize boolean keys'
    Assert-True ($Task2LogContent -match 'seen_keys\s*\[\s*canonical\s*\]') 'Logger must handle canonical key collisions without depending on pairs order'
    Assert-True ($Task2LogContent -match '<canonical-key-collision>') 'Logger must emit a stable collision placeholder'
    Assert-True ($Task2LogContent -match 'pcall\s*\(\s*printf\s*,') 'Logger must protect the printf sink with pcall'
    foreach ($BoundedLogMarker in @('MAX_NATIVE_PAYLOAD_BYTES = 1024','CHUNK_BODY_BYTES = 896','GA_LOG_CHUNK','pcall(printf, "%s", native_payload)')) {
        Assert-True ($Task2LogContent.Contains($BoundedLogMarker)) "Logger bounded native-sink contract is missing: $BoundedLogMarker"
    }
    foreach ($BoundedLogCase in @('log_native_payload_is_bounded_and_reconstructable','log_small_payload_remains_one_line')) {
        Assert-True ($Task4DomainTestContent.Contains($BoundedLogCase)) "Logger runtime regression is missing: $BoundedLogCase"
    }
}
if (Test-Path -LiteralPath $Task2RngPath) {
    $Task2RngContent = Get-Content -LiteralPath $Task2RngPath -Raw
    Assert-True ($Task2RngContent -match 'minimum\s*~=\s*minimum') 'RNG must reject NaN minimum bounds'
    Assert-True ($Task2RngContent -match 'maximum\s*~=\s*maximum') 'RNG must reject NaN maximum bounds'
    Assert-True ($Task2RngContent -match 'math\.huge') 'RNG must reject infinite bounds and spans'
    Assert-True ($Task2RngContent -match 'local\s+span\s*=\s*maximum\s*-\s*minimum\s*\+\s*1') 'RNG must validate its computed span before modulo'
    Assert-True ($Task2RngContent -match 'value\s*==\s*math\.huge') 'RNG seed normalization must reject positive infinity'
    Assert-True ($Task2RngContent -match 'value\s*==\s*-math\.huge') 'RNG seed normalization must reject negative infinity'
}

$IsRepositoryCheckout = Test-Path -LiteralPath (Join-Path $RepoRoot '.git')
if ($IsRepositoryCheckout) {
    $Task10RequiredFiles = @(
        'tools\New-CompatibilityReport.ps1',
        'schemas\compatibility-manifest-v1.md'
    )
    foreach ($RelativePath in $Task10RequiredFiles) {
        Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)) "Task 10 contract is missing: $RelativePath"
    }

    $BuildPath = Join-Path $RepoRoot 'tools\Build-GammaArena.ps1'
    if (Test-Path -LiteralPath $BuildPath) {
        $BuildContent = Get-Content -LiteralPath $BuildPath -Raw
        foreach ($Field in @(
            'addon_version',
            'state_schema_version',
            'session_schema_version',
            'fight_spec_schema_version',
            'generator_version',
            'catalog_revision',
            'layout_revision',
            'compatibility_manifest_version'
        )) {
            Assert-True ($BuildContent -match ("(?m)^\s*" + [regex]::Escape($Field) + "\s*=")) "Release manifest must record $Field"
        }
        Assert-True ($BuildContent -match 'Get-OrdinalSortedPaths') 'Release manifest files must be sorted ordinally'
        Assert-True ($BuildContent -match 'Get-FileHash[^\r\n]+SHA256') 'Release manifest must checksum raw staged files with SHA-256'
        Assert-True ($BuildContent -match 'UTF8Encoding\(\$false\)') 'Release manifest must use UTF-8 without BOM'
        Assert-True ($BuildContent -notmatch 'Copy-GameDataTree\s+\(Join-Path\s+\$RepoRoot\s+''dev\\gamedata''\)\s+\$StageGameData\s*(?:\r?\n)+\s*if\s*\(\$Configuration\s+-eq\s+''Release''\)') 'Release package must not copy Dev test files'
    }

    if (Test-Path -LiteralPath $MigrationPath) {
        foreach ($Marker in @(
            'CURRENT_ADDON_VERSION',
            'migrate_v0_to_v1',
            'while schema_version < CURRENT_SETTINGS_SCHEMA',
            'GA_ADDON_VERSION_UNKNOWN',
            'GA_ADDON_VERSION_CHANGED',
            'active_fight_compatible = false',
            'commit_remove_keys = TRANSIENT_INTENT_KEYS',
            'launch_pending',
            'resume_pending'
        )) {
            Assert-True ($MigrationContent -match [regex]::Escape($Marker)) "Task 10 migration policy must cover $Marker"
        }
        Assert-True ($MigrationContent -notmatch 'snapshot\.addon_version\s*==\s*nil\s+or') 'Schema-v1 state without addon_version must not be treated as current-version state'
        $Task10MigrationTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_migrations.script'
        Assert-True (Test-Path -LiteralPath $Task10MigrationTestPath) 'Task 10 Dev migration tests are missing'
        if (Test-Path -LiteralPath $Task10MigrationTestPath) {
            $Task10MigrationTestContent = Get-Content -LiteralPath $Task10MigrationTestPath -Raw
            foreach ($CaseName in @(
                'schema_v1_without_addon_version_is_incompatible',
                'schema_v1_current_addon_preserves_transient_intents',
                'schema_v1_different_addon_clears_transient_intents',
                'GA_ADDON_VERSION_UNKNOWN',
                'GA_ADDON_VERSION_CHANGED',
                'active_fight_compatible'
            )) {
                Assert-True ($Task10MigrationTestContent -match [regex]::Escape($CaseName)) "Task 10 Dev migration tests must cover $CaseName"
            }
        }
    }


    $CompatibilityReportPath = Join-Path $RepoRoot 'tools\New-CompatibilityReport.ps1'
    if (Test-Path -LiteralPath $CompatibilityReportPath) {
        $CompatibilityReportContent = Get-Content -LiteralPath $CompatibilityReportPath -Raw
        foreach ($SafetyMarker in @('Get-SafeContainedFile', 'Get-SafeTreeFiles', 'Unsafe reparse point encountered', 'FileAttributes]::ReparsePoint')) {
            Assert-True ($CompatibilityReportContent -match [regex]::Escape($SafetyMarker)) "Compatibility report must implement descendant safety marker: $SafetyMarker"
        }
        $Task10TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gamma-arena-compatibility-" + [Guid]::NewGuid().ToString('N'))
        function Write-Task10FixtureFile([string]$Root, [string]$RelativePath, [string]$Content) {
            $Path = Join-Path $Root $RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
            [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
            return $Path
        }
        function Get-Task10TreeFingerprint([string[]]$Roots) {
            $Rows = @()
            foreach ($Root in $Roots) {
                foreach ($File in @(Get-ChildItem -LiteralPath $Root -File -Recurse)) {
                    $Rows += ($File.FullName + '|' + (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash)
                }
            }
            [Array]::Sort($Rows, [StringComparer]::Ordinal)
            return ($Rows -join "`n")
        }

        try {
            $AnomalyRoot = Join-Path $Task10TempRoot 'Anomaly'
            $Mo2Root = Join-Path $Task10TempRoot 'GAMMA'
            $ReleaseRoot = Join-Path $Task10TempRoot 'release\gamedata'
            $Profile = 'Fixture Profile'
            $null = Write-Task10FixtureFile $AnomalyRoot 'bin\AnomalyDX11.exe' 'dx11'
            $null = Write-Task10FixtureFile $AnomalyRoot 'bin\AnomalyDX9.exe' 'dx9'
            $null = Write-Task10FixtureFile $AnomalyRoot 'bin\VerifiedDX11.exe' 'verified'
            $null = Write-Task10FixtureFile $AnomalyRoot 'gamedata\scripts\ui_main_menu.script' 'base menu'

            $EffectiveMenuXmlPath = Write-Task10FixtureFile $Mo2Root 'mods\Framework\gamedata\configs\ui\ui_mm_main.xml' 'framework menu xml'
            $EffectiveAxrPath = Write-Task10FixtureFile $Mo2Root 'mods\Framework\gamedata\scripts\axr_main.script' 'axr'
            $EffectiveBindPath = Write-Task10FixtureFile $Mo2Root 'mods\Framework\gamedata\scripts\bind_stalker_ext.script' 'bind'
            $EffectiveLoadoutPath = Write-Task10FixtureFile $Mo2Root 'mods\Direct Root\scripts\xrs_rnd_npc_loadout.script' 'wrapperless loadout'
            $EffectiveMenuPath = Write-Task10FixtureFile $Mo2Root 'mods\High Priority\gamedata\scripts\ui_main_menu.script' 'effective menu'
            $EffectiveFactionPath = Write-Task10FixtureFile $Mo2Root 'mods\High Priority\gamedata\scripts\ui_mm_faction_select.script' 'faction select'
            $null = Write-Task10FixtureFile $Mo2Root 'mods\High Priority\gamedata\scripts\modxml_gamma_arena.script' 'conflicting patch'
            $ModListPath = Write-Task10FixtureFile $Mo2Root ("profiles\$Profile\modlist.txt") "-Disabled`r`n+Framework`r`n+Direct Root`r`n+High Priority`r`n"

            $null = Write-Task10FixtureFile $ReleaseRoot 'configs\ui\modxml_gamma_arena.xml' 'unique dxml'
            $null = Write-Task10FixtureFile $ReleaseRoot 'scripts\modxml_gamma_arena.script' 'release patch'

            $BeforeFingerprint = Get-Task10TreeFingerprint @($AnomalyRoot, $Mo2Root)
            $Arguments = @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $CompatibilityReportPath,
                '-AnomalyRoot', $AnomalyRoot, '-Mo2Root', $Mo2Root, '-Profile', $Profile,
                '-ReleaseRoot', $ReleaseRoot
            )
            $FirstReport = (& powershell.exe @Arguments 2>&1 | Out-String).TrimEnd()
            $FirstExit = $LASTEXITCODE
            $SecondReport = (& powershell.exe @Arguments 2>&1 | Out-String).TrimEnd()
            $SecondExit = $LASTEXITCODE
            $AfterFingerprint = Get-Task10TreeFingerprint @($AnomalyRoot, $Mo2Root)

            Assert-True ($FirstExit -eq 0 -and $SecondExit -eq 0) 'Compatibility report must succeed for an isolated complete fixture'
            Assert-True ($FirstReport -ceq $SecondReport) 'Compatibility report must be deterministic for identical inputs'
            Assert-True ($BeforeFingerprint -ceq $AfterFingerprint) 'Compatibility report must never write to Anomaly or MO2 roots'
            Assert-True ($FirstReport -match [regex]::Escape(('Active MO2 profile: `' + $Profile + '`'))) 'Compatibility report must identify the active MO2 profile'
            Assert-True ($FirstReport -match [regex]::Escape((Get-FileHash -LiteralPath $ModListPath -Algorithm SHA256).Hash)) 'Compatibility report must hash active modlist.txt'
            foreach ($ProviderPath in @($EffectiveMenuXmlPath, $EffectiveAxrPath, $EffectiveBindPath, $EffectiveLoadoutPath, $EffectiveMenuPath, $EffectiveFactionPath)) {
                Assert-True ($FirstReport -match [regex]::Escape((Get-FileHash -LiteralPath $ProviderPath -Algorithm SHA256).Hash)) "Compatibility report must hash every effective provider: $ProviderPath"
            }
            Assert-True ($FirstReport -match 'MO2 mod: Direct Root') 'Compatibility report must resolve wrapperless mod data roots'
            foreach ($RequiredName in @('AnomalyDX9.exe','AnomalyDX11.exe','VerifiedDX11.exe','ui_main_menu.script','ui_mm_main.xml','ui_mm_faction_select.script','axr_main.script','bind_stalker_ext.script','xrs_rnd_npc_loadout.script')) {
                Assert-True ($FirstReport -match [regex]::Escape($RequiredName)) "Compatibility report must list $RequiredName"
            }
            Assert-True ($FirstReport -match '0 blocking overlaps') 'Unique DLTX/DXML release files must produce 0 blocking overlaps'
            Assert-True ($FirstReport -match '1 warning overlap') 'Exact same-path overlap must be a warning'
            Assert-True ($FirstReport -match 'explicit review') 'Same-path overlap warnings must require explicit review'
            Assert-True ($FirstReport -match 'Forbidden core overrides:\s*0') 'Fixture release must report no forbidden core override'

            $PreviousErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'

            Remove-Item -LiteralPath $EffectiveFactionPath -Force
            $MissingProviderOutput = (& powershell.exe @Arguments 2>&1 | Out-String)
            $MissingProviderExit = $LASTEXITCODE
            Assert-True ($MissingProviderExit -ne 0) 'Compatibility report must fail nonzero when a critical provider is missing'
            Assert-True ($MissingProviderOutput -match 'Missing critical providers:\s*1') 'Compatibility report must count missing critical providers'
            Assert-True ($MissingProviderOutput -match 'INCOMPLETE') 'Compatibility report must label missing-provider evidence incomplete'
            $EffectiveFactionPath = Write-Task10FixtureFile $Mo2Root 'mods\High Priority\gamedata\scripts\ui_mm_faction_select.script' 'faction select'

            $null = Write-Task10FixtureFile $Mo2Root 'Outside\placeholder.txt' 'traversal target'
            $InvalidModNames = @('..\Outside', 'Nested\Child', 'Nested/Child', 'Bad:Name', 'Trailing.', 'Trailing ', 'CON')
            $null = Write-Task10FixtureFile $Mo2Root 'mods\Nested\Child\placeholder.txt' 'nested target'
            $InvalidIndex = 0
            foreach ($InvalidModName in $InvalidModNames) {
                $InvalidProfile = "Invalid Mod $InvalidIndex"
                $null = Write-Task10FixtureFile $Mo2Root ("profiles\$InvalidProfile\modlist.txt") ("+" + $InvalidModName + "`r`n")
                $InvalidOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $InvalidProfile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
                $InvalidExit = $LASTEXITCODE
                Assert-True ($InvalidExit -ne 0 -and $InvalidOutput -match 'Enabled MO2 mod name is invalid') "Compatibility report must reject non-component enabled mod name: $InvalidModName"
                $InvalidIndex += 1
            }

            foreach ($InvalidProfileName in @('..\Outside', 'Nested\Profile', 'Nested/Profile', 'Bad:Profile', 'Trailing.', 'Trailing ', 'CON')) {
                $InvalidProfileOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $InvalidProfileName -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
                $InvalidProfileExit = $LASTEXITCODE
                Assert-True ($InvalidProfileExit -ne 0 -and $InvalidProfileOutput -match 'MO2 profile name is invalid') "Compatibility report must reject non-component profile name: $InvalidProfileName"
            }

            $OutsideProfileRoot = Join-Path $Task10TempRoot 'outside-profile'
            $null = Write-Task10FixtureFile $OutsideProfileRoot 'modlist.txt' "+Framework`r`n+Direct Root`r`n+High Priority`r`n"
            $EscapedProfilePath = Join-Path $Mo2Root 'profiles\Escaped Profile'
            $null = New-Item -ItemType Junction -Path $EscapedProfilePath -Target $OutsideProfileRoot
            $EscapedProfileOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile 'Escaped Profile' -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $EscapedProfileExit = $LASTEXITCODE
            Assert-True ($EscapedProfileExit -ne 0 -and $EscapedProfileOutput -match 'Resolved MO2 profile escapes profiles root') 'Compatibility report must reject a profile junction outside profiles root'

            $OutsideModRoot = Join-Path $Task10TempRoot 'outside-mod'
            $null = Write-Task10FixtureFile $OutsideModRoot 'placeholder.txt' 'escaped mod'
            $EscapedModPath = Join-Path $Mo2Root 'mods\Escaped Mod'
            $null = New-Item -ItemType Junction -Path $EscapedModPath -Target $OutsideModRoot
            $EscapedModProfile = 'Escaped Mod Profile'
            $null = Write-Task10FixtureFile $Mo2Root ("profiles\$EscapedModProfile\modlist.txt") "+Escaped Mod`r`n"
            $EscapedModOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $EscapedModProfile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $EscapedModExit = $LASTEXITCODE
            Assert-True ($EscapedModExit -ne 0 -and $EscapedModOutput -match 'Resolved enabled MO2 mod escapes mods root') 'Compatibility report must reject a mod junction outside mods root'

            $DataEscapeModRoot = Join-Path $Mo2Root 'mods\Data Escape'
            $OutsideDataRoot = Join-Path $Task10TempRoot 'outside-data'
            $null = Write-Task10FixtureFile $DataEscapeModRoot 'placeholder.txt' 'data escape mod'
            $null = Write-Task10FixtureFile $OutsideDataRoot 'scripts\xrs_rnd_npc_loadout.script' 'escaped data'
            $null = New-Item -ItemType Junction -Path (Join-Path $DataEscapeModRoot 'gamedata') -Target $OutsideDataRoot
            $DataEscapeProfile = 'Data Escape Profile'
            $null = Write-Task10FixtureFile $Mo2Root ("profiles\$DataEscapeProfile\modlist.txt") "+Data Escape`r`n"
            $DataEscapeOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $DataEscapeProfile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $DataEscapeExit = $LASTEXITCODE
            Assert-True ($DataEscapeExit -ne 0 -and $DataEscapeOutput -match 'Resolved MO2 mod data root escapes enabled mod root') 'Compatibility report must reject a gamedata junction outside its enabled mod root'

            $ProviderEscapeModRoot = Join-Path $Mo2Root 'mods\Provider Escape'
            $ProviderEscapeScripts = Join-Path $Task10TempRoot 'outside-provider-scripts'
            $null = Write-Task10FixtureFile $ProviderEscapeModRoot 'gamedata\placeholder.txt' 'provider escape mod'
            $null = Write-Task10FixtureFile $ProviderEscapeScripts 'ui_main_menu.script' 'escaped provider'
            $null = New-Item -ItemType Junction -Path (Join-Path $ProviderEscapeModRoot 'gamedata\scripts') -Target $ProviderEscapeScripts
            $ProviderEscapeProfile = 'Provider Escape Profile'
            $null = Write-Task10FixtureFile $Mo2Root ("profiles\$ProviderEscapeProfile\modlist.txt") "+Framework`r`n+Direct Root`r`n+High Priority`r`n+Provider Escape`r`n"
            $ProviderEscapeOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $ProviderEscapeProfile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $ProviderEscapeExit = $LASTEXITCODE
            Assert-True ($ProviderEscapeExit -ne 0 -and $ProviderEscapeOutput -match 'Unsafe reparse point encountered') 'Compatibility report must reject a nested provider-directory junction before hashing'

            $OverlapEscapeModRoot = Join-Path $Mo2Root 'mods\Overlap Escape'
            $OverlapEscapeTextures = Join-Path $Task10TempRoot 'outside-overlap-textures'
            $OverlapRelativePath = 'textures\gamma_arena\overlap.dds'
            $null = Write-Task10FixtureFile $ReleaseRoot $OverlapRelativePath 'release overlap'
            $null = Write-Task10FixtureFile $OverlapEscapeModRoot 'gamedata\placeholder.txt' 'overlap escape mod'
            $null = Write-Task10FixtureFile $OverlapEscapeTextures 'gamma_arena\overlap.dds' 'escaped overlap'
            $null = New-Item -ItemType Junction -Path (Join-Path $OverlapEscapeModRoot 'gamedata\textures') -Target $OverlapEscapeTextures
            $OverlapEscapeProfile = 'Overlap Escape Profile'
            $null = Write-Task10FixtureFile $Mo2Root ("profiles\$OverlapEscapeProfile\modlist.txt") "+Framework`r`n+Direct Root`r`n+High Priority`r`n+Overlap Escape`r`n"
            $OverlapEscapeOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $OverlapEscapeProfile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $OverlapEscapeExit = $LASTEXITCODE
            Assert-True ($OverlapEscapeExit -ne 0 -and $OverlapEscapeOutput -match 'Unsafe reparse point encountered') 'Compatibility report must reject a nested overlap-directory junction before hashing'

            $UnsafeReleaseRoot = Join-Path $Task10TempRoot 'unsafe-release'
            $OutsideReleaseTree = Join-Path $Task10TempRoot 'outside-release-tree'
            $null = Write-Task10FixtureFile $UnsafeReleaseRoot 'safe\file.txt' 'safe release file'
            $null = Write-Task10FixtureFile $OutsideReleaseTree 'escaped.txt' 'escaped release file'
            $null = New-Item -ItemType Junction -Path (Join-Path $UnsafeReleaseRoot 'escaped') -Target $OutsideReleaseTree
            $UnsafeReleaseOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $Profile -ReleaseRoot $UnsafeReleaseRoot 2>&1 | Out-String)
            $UnsafeReleaseExit = $LASTEXITCODE
            Assert-True ($UnsafeReleaseExit -ne 0 -and $UnsafeReleaseOutput -match 'Unsafe reparse point encountered') 'Compatibility report must reject a nested release-root junction before recursive enumeration'

            $ExecutableEscapeAnomaly = Join-Path $Task10TempRoot 'executable-escape-anomaly'
            $OutsideExecutableBin = Join-Path $Task10TempRoot 'outside-executable-bin'
            $null = Write-Task10FixtureFile $ExecutableEscapeAnomaly 'placeholder.txt' 'anomaly root'
            $null = Write-Task10FixtureFile $OutsideExecutableBin 'AnomalyDX11.exe' 'escaped executable'
            $null = New-Item -ItemType Junction -Path (Join-Path $ExecutableEscapeAnomaly 'bin') -Target $OutsideExecutableBin
            $ExecutableEscapeOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $ExecutableEscapeAnomaly -Mo2Root $Mo2Root -Profile $Profile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $ExecutableEscapeExit = $LASTEXITCODE
            Assert-True ($ExecutableEscapeExit -ne 0 -and $ExecutableEscapeOutput -match 'Unsafe reparse point encountered') 'Compatibility report must reject an executable-bin junction before hashing'

            $FileSymlinkTarget = Write-Task10FixtureFile $Task10TempRoot 'outside-file-provider.script' 'escaped file provider'
            $FileSymlinkModRoot = Join-Path $Mo2Root 'mods\File Symlink Escape'
            $FileSymlinkParent = Join-Path $FileSymlinkModRoot 'gamedata\scripts'
            $null = New-Item -ItemType Directory -Path $FileSymlinkParent -Force
            $FileSymlinkPath = Join-Path $FileSymlinkParent 'ui_main_menu.script'
            $FileSymlinkSupported = $false
            try {
                $null = New-Item -ItemType SymbolicLink -Path $FileSymlinkPath -Target $FileSymlinkTarget -ErrorAction Stop
                $FileSymlinkSupported = $true
            }
            catch {
                Write-Host 'INFO: direct file symlink fixture unavailable; reparse-leaf rejection remains statically required'
            }
            if ($FileSymlinkSupported) {
                $FileSymlinkProfile = 'File Symlink Profile'
                $null = Write-Task10FixtureFile $Mo2Root ("profiles\$FileSymlinkProfile\modlist.txt") "+Framework`r`n+Direct Root`r`n+High Priority`r`n+File Symlink Escape`r`n"
                $FileSymlinkOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile $FileSymlinkProfile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
                $FileSymlinkExit = $LASTEXITCODE
                Assert-True ($FileSymlinkExit -ne 0 -and $FileSymlinkOutput -match 'Unsafe reparse point encountered') 'Compatibility report must reject a direct provider-file symlink before hashing'
            }

            $MissingRootOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot (Join-Path $Task10TempRoot 'missing') -Mo2Root $Mo2Root -Profile $Profile -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $MissingRootExit = $LASTEXITCODE
            Assert-True ($MissingRootExit -ne 0 -and $MissingRootOutput -match 'Anomaly root does not exist') 'Compatibility report must fail clearly for a missing Anomaly root'

            $MissingProfileOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CompatibilityReportPath -AnomalyRoot $AnomalyRoot -Mo2Root $Mo2Root -Profile 'Missing Profile' -ReleaseRoot $ReleaseRoot 2>&1 | Out-String)
            $MissingProfileExit = $LASTEXITCODE
            $ErrorActionPreference = $PreviousErrorActionPreference
            Assert-True ($MissingProfileExit -ne 0 -and $MissingProfileOutput -match 'MO2 profile does not exist') 'Compatibility report must fail clearly for a missing profile'
        }
        finally {
            if (Test-Path -LiteralPath $Task10TempRoot) {
                Remove-Item -LiteralPath $Task10TempRoot -Recurse -Force
            }
        }
    }
}

$Task11DirectorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_tactical_director.script'
$Task11TestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_tactical_director.script'
Assert-True (Test-Path -LiteralPath $Task11DirectorPath) 'Tactical director production script is missing'
Assert-True (Test-Path -LiteralPath $Task11TestPath) 'Tactical director dev suite is missing'
if (Test-Path -LiteralPath $Task11DirectorPath) {
    $Task11DirectorContent = Get-Content -LiteralPath $Task11DirectorPath -Raw
    Assert-True ($Task11DirectorContent -match 'function\s+Director:(begin|observe|update|accept_hint|stop|snapshot)\s*\(') 'Tactical director public lifecycle is missing'
    foreach ($Task11Marker in @('is_modular_newer', 'deadline_reached', 'local_evidence', 'evidence_sequence')) {
        Assert-True ($Task11DirectorContent.Contains($Task11Marker)) "Tactical director temporal/privacy contract is missing marker: $Task11Marker"
    }
    Assert-True ($Task11DirectorContent -match 'function\s+new\s*\(' -and $Task11DirectorContent -match 'gamma_arena_rng\.derive_seed') 'Tactical director constructor/RNG contract is missing'
    Assert-True ($Task11DirectorContent -notmatch 'db\.actor|xr_logic|make_object_visible_somewhen|set_enemy|math\.random') 'Pure director must not use engine globals or omniscient APIs'
    Assert-True ($Task11DirectorContent -notmatch 'participant\.slot\s*~=\s*index') 'Tactical director must not require logical participant slots to equal dense array indexes.'
    Assert-True ($Task11DirectorContent -match 'self\.participant_by_slot\s*=\s*participant_by_slot') 'Tactical director must retain a logical-slot participant map alongside dense iteration order.'
    Assert-True ($Task11DirectorContent -match 'self\.participant_by_slot\[evidence\.observer_slot\]') 'Tactical evidence validation must address participants by logical slot.'
}
$Task11DomainContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_domain.script') -Raw
Assert-True ($Task11DomainContent -match 'gamma_arena_test_tactical_director\.run\s*\(\s*run_case_fn\s*\)') 'Dev domain suite must execute tactical director tests'
$Task11AdapterTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_tactical_adapter.script'
Assert-True (Test-Path -LiteralPath $Task11AdapterTestPath) 'Tactical adapter dev suite is missing'
Assert-True ($Task11DomainContent -match 'gamma_arena_test_tactical_adapter\.run\s*\(\s*run_case_fn\s*\)') 'Dev domain suite must execute tactical adapter tests'
if (Test-Path -LiteralPath $Task11AdapterTestPath) {
    $Task11AdapterTestContent = Get-Content -LiteralPath $Task11AdapterTestPath -Raw
    $Task11LogicalSlotCase = 'adapter_accepts_nonsequential_logical_slots'
    $Task11LogicalSlotRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($Task11LogicalSlotCase) + '"\s*,\s*fn\s*=\s*accepts_nonsequential_logical_slots\s*\}'
    Assert-True (([regex]::Matches($Task11AdapterTestContent, $Task11LogicalSlotRegistration)).Count -eq 1) 'Tactical adapter regression must register nonsequential logical-slot coverage exactly once.'
    $Task11RealDirectorSlotCase = 'adapter_real_director_accepts_nonsequential_logical_slots'
    $Task11RealDirectorSlotRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($Task11RealDirectorSlotCase) + '"\s*,\s*fn\s*=\s*real_director_accepts_nonsequential_logical_slots\s*\}'
    Assert-True (([regex]::Matches($Task11AdapterTestContent, $Task11RealDirectorSlotRegistration)).Count -eq 1) 'Real tactical adapter/director regression must register nonsequential logical-slot coverage exactly once.'
    $Task11RealDirectorSlotBody = [regex]::Match($Task11AdapterTestContent, 'local\s+function\s+real_director_accepts_nonsequential_logical_slots\(\)[\s\S]*?\r?\nend').Value
    Assert-True ($Task11RealDirectorSlotBody -match 'real_director\s*=\s*true' -and
        $Task11RealDirectorSlotBody -match 'slot\s*=\s*2' -and
        $Task11RealDirectorSlotBody -match 'adapter:begin' -and
        $Task11RealDirectorSlotBody -match 'adapter:update') 'Nonsequential slot integration must cross the real tactical adapter/director begin and evidence-update paths.'
}
$Task11AdapterPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_tactical_adapter.script'
Assert-True (Test-Path -LiteralPath $Task11AdapterPath) 'Tactical engine adapter production script is missing'
if (Test-Path -LiteralPath $Task11AdapterPath) {
    $Task11AdapterContent = Get-Content -LiteralPath $Task11AdapterPath -Raw
    foreach ($Task11Method in @('begin', 'update', 'record_death', 'stop', 'snapshot')) {
        Assert-True ($Task11AdapterContent -match "function\s+Adapter:$Task11Method\s*\(") "Tactical adapter public method is missing: $Task11Method"
    }
    foreach ($Task11Marker in @('best_danger', 'best_enemy', 'get_enemy', 'memory_position', 'grenade', 'see', 'xr_logic.configure_schemes', 'xr_logic.activate_by_section', 'xr_logic.switch_to_section', 'hint_requested', 'actor.position')) {
        Assert-True ($Task11AdapterContent.Contains($Task11Marker)) "Tactical adapter contract is missing marker: $Task11Marker"
    }
    Assert-True ($Task11AdapterContent -match 'pcall') 'Tactical adapter engine reads must be guarded'
    Assert-True ($Task11AdapterContent -match 'combat_owned\s*=\s*sees_actor\.value\s*==\s*true') 'Only direct actor visibility may retain native combat ownership after target memory becomes stale'
    Assert-True ($Task11AdapterContent -notmatch 'combat_owned\s*=\s*best_enemy\.value\s*~=\s*nil') 'Remembered best_enemy must not permanently block director search movement'
    Assert-True ($Task11AdapterContent -notmatch 'type\s*\(\s*native\s*\)\s*~=\s*["'']table["'']') 'Engine danger_object namespace must not be rejected solely because its Lua type is not table'
    Assert-True ($Task11AdapterContent -notmatch 'set_dest_level_vertex_id|set_sight|set_item|set_enemy|make_object_visible_somewhen|math\.random') 'Tactical adapter must not override native combat or use global randomness'
    Assert-True ($Task11AdapterContent -notmatch 'opponent\.slot\s*~=\s*index') 'Tactical adapter must not require logical opponent slots to equal dense array indexes.'
    Assert-True ($Task11AdapterContent -match 'participant_by_slot\[opponent\.slot\]\s*~=\s*nil') 'Tactical adapter must reject duplicate logical opponent slots through its slot map.'
}
$Task11EntityContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_entity_adapter.script') -Raw
Assert-True ($Task11EntityContent -match 'validated_spec\.tactical_routes') 'Entity adapter must pass every validated Arena route to the tactical director'
Assert-True ($Task11EntityContent.Contains('STOPPING')) 'Entity adapter must retain failed tactical stop ownership for bounded retry'
foreach ($Task11Marker in @('stable_encode', 'deps.tactical', 'tactical_disabled', 'GA_DIRECTOR_RUNTIME_DISABLED', 'record_death', 'stop_tactical')) {
    Assert-True ($Task11EntityContent.Contains($Task11Marker)) "Entity tactical lifecycle is missing marker: $Task11Marker"
}
Assert-True ($Task11EntityContent -match 'function\s+EntityAdapter:reconcile_active_deaths\s*\(') 'ACTIVE entity updates must reconcile dead registered opponents when an external death callback is missed'
$Task11OrchestratorContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script') -Raw
Assert-True ($Task11OrchestratorContent -match 'function\s+Orchestrator:reconcile_active_victory\s*\(') 'ACTIVE orchestration must derive victory from the reconciled living-opponent count'
Assert-True ($Task11EntityContent -match 'tactical_started\s*=\s*true[\s\S]{0,300}set_state\("READY"\)') 'Tactical bind must be part of READY staging'
Assert-True ($Task11EntityContent -match 'function\s+EntityAdapter:activate_ready[\s\S]{0,2500}set_actor_hostile[\s\S]{0,1000}set_state\("ACTIVE"\)') 'READY activation must apply hostility before ACTIVE'
$Task11BootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
Assert-True ($Task11BootstrapContent -match 'gamma_arena_tactical_adapter\.new') 'Bootstrap must compose the production tactical adapter'
Assert-True ($Task11BootstrapContent -match 'function\s+TacticalProxy:begin[\s\S]{0,500}ensure_adapter') 'Tactical adapter must be created lazily after the Arena actor exists'
Assert-True ($Task11BootstrapContent -match 'function\s+TacticalProxy:stop[\s\S]{0,400}adapter:stop[\s\S]{0,200}if\s+stopped\.ok[\s\S]{0,100}self\.active\s*=\s*nil') 'Tactical proxy must retain a failed adapter stop for retry'
$Task11TacticalConfigPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx'
Assert-True (Test-Path -LiteralPath $Task11TacticalConfigPath) 'Tactical director LTX is missing'
$Task11TacticalConfigContent = Get-Content -LiteralPath $Task11TacticalConfigPath -Raw
Assert-True ($Task11TacticalConfigContent -notmatch 'bar_arena_monstr_walk') 'Tactical human walkers must never use the monster patrol'
Assert-True ($Task11TacticalConfigContent -match '\[walker@ga_bar_arena_walk_1_1\][\s\S]{0,300}path_walk\s*=\s*bar_arena_walk_1_1') 'Tactical config must include the vanilla sixth human patrol'
Assert-True (([regex]::Matches($Task11TacticalConfigContent, '(?m)^out_restr\s*=\s*bar_arena_restrictor\s*$')).Count -eq 6) 'Every tactical human walker must use the vanilla Arena restrictor'
$Task11CompatContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script') -Raw
foreach ($Task11Marker in @(
    'GA_PREFLIGHT_DIRECTOR_API_MISSING',
    'GA_PREFLIGHT_DIRECTOR_CONFIG_INVALID',
    'GA_PREFLIGHT_DIRECTOR_SECTION_MISSING',
    'GA_PREFLIGHT_DIRECTOR_LOOK_PATH_MISSING',
    'xr_logic.configure_schemes',
    'xr_logic.activate_by_section',
    'xr_logic.switch_to_section'
)) {
    Assert-True ($Task11CompatContent.Contains($Task11Marker)) "Tactical preflight contract is missing marker: $Task11Marker"
}

$Task12BootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
$Task12OrchestratorContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script') -Raw
$Task12EntityContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_entity_adapter.script') -Raw
$Task12CompatContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script') -Raw
Assert-True ($Task12BootstrapContent -match 'gamma_arena_layout_adapter\.new') 'Bootstrap must compose one cached runtime layout adapter'
foreach ($Task12Marker in @('level.vertex_in_direction', 'level.vertex_position', 'vector()', 'GA_LAYOUT_BASE_ANCHOR_INVALID')) {
    Assert-True ($Task12BootstrapContent.Contains($Task12Marker)) "Bootstrap resolved-layout port is missing marker: $Task12Marker"
}
Assert-True ($Task12BootstrapContent -match 'gamma_arena_fight_builder\.generate\(session,\s*fight_index,\s*catalog_snapshot,\s*resolved_layout\)') 'Bootstrap universal builder port must receive the resolved physical layout'
Assert-True ($Task12BootstrapContent -match 'gamma_arena_validator\.validate_runtime\(spec,\s*catalog_snapshot,\s*resolved_layout') 'Bootstrap validator port must receive the same resolved physical layout and runtime profile resolver'
Assert-True ($Task12BootstrapContent.Contains('set_character_community') -and $Task12BootstrapContent.Contains('character_community')) 'Bootstrap must bind runtime-community mutation and readback ports'
Assert-True ($Task12OrchestratorContent -match 'function\s+Orchestrator:npc_on_net_spawn\s*\(' -and $Task12OrchestratorContent.Contains('on_npc_net_spawn')) 'Orchestrator must delegate the owned NPC net-spawn boundary'
foreach ($RuntimeCommunityMarker in @('function EntityAdapter:on_npc_net_spawn','GA_ENTITY_RUNTIME_COMMUNITY_OWNER_MISMATCH','GA_ENTITY_RUNTIME_COMMUNITY_SET_FAILED','GA_ENTITY_RUNTIME_COMMUNITY_READ_FAILED','GA_ENTITY_RUNTIME_COMMUNITY_VERIFY_FAILED','set_runtime_community','runtime_community')) {
    Assert-True ($Task12EntityContent.Contains($RuntimeCommunityMarker)) "Runtime NPC community isolation is missing marker: $RuntimeCommunityMarker"
}
Assert-True ($Task12OrchestratorContent -match 'function\s+Orchestrator:preflight_fight\s*\([\s\S]{0,900}layout_snapshot\s*\([\s\S]{0,700}deps\.generator[\s\S]{0,300}layout\.value[\s\S]{0,500}deps\.validator[\s\S]{0,300}layout\.value') 'Fight preflight must thread one resolved layout through generation and validation'
Assert-True ($Task12EntityContent.Contains('participant.spawn') -and $Task12EntityContent.Contains('tactical_route')) 'Entity adapter must consume validated physical spawns separately from tactical routes'
Assert-True ($Task12EntityContent -notmatch 'self\.deps\.resolve_spawn') 'Entity spawning must not resolve patrol routes after FightSpec validation'
foreach ($Task12Marker in @('level.vertex_in_direction', 'level.vertex_position', 'vector')) {
    Assert-True ($Task12CompatContent.Contains($Task12Marker)) "Preflight must require resolved-layout engine capability: $Task12Marker"
}

foreach ($Task13Marker in @('WOUNDED_PENDING', 'MISSING_PENDING', 'DEFEATED_DEAD', 'DEFEATED_WOUNDED', 'DEFEATED_MISSING', 'TERMINAL_GRACE_MS', 'proved_online', 'is_critically_wounded', 'GA_OPPONENT_STATE_CHANGED')) {
    Assert-True ($Task12EntityContent.Contains($Task13Marker)) "Authoritative opponent terminal-state contract is missing marker: $Task13Marker"
}
Assert-True ($Task12EntityContent -match 'function\s+EntityAdapter:transition_opponent\s*\(') 'Entity adapter must centralize opponent terminal transitions'
Assert-True ($Task12EntityContent -match 'function\s+EntityAdapter:terminal_summary\s*\(') 'Entity adapter must expose final terminal counts by reason'
Assert-True ($Task12BootstrapContent.Contains('critically_wounded') -and $Task12BootstrapContent.Contains('log_info')) 'Bootstrap must bind wound evidence and terminal transition diagnostics'
Assert-True ($Task12CompatContent.Contains('game_object.critically_wounded')) 'Preflight must require the critical-wound query used by victory reconciliation'
Assert-True ($Task12OrchestratorContent -match 'show_victory[\s\S]{0,900}terminal_summary') 'Victory logging must include authoritative terminal counts'
$TransitionStart = $Task12EntityContent.IndexOf('function EntityAdapter:transition_opponent')
$TransitionEnd = $Task12EntityContent.IndexOf('function EntityAdapter:accept_registered_death', $TransitionStart)
Assert-True ($TransitionStart -ge 0 -and $TransitionEnd -gt $TransitionStart) 'Opponent transition logger must remain structurally testable'
$TransitionContent = $Task12EntityContent.Substring($TransitionStart, $TransitionEnd - $TransitionStart)
Assert-True ($TransitionContent -notmatch 'fight_key\s*=\s*self\.fight_key') 'Routine opponent transitions must not repeat the complete FightSpec in every native log call'
foreach ($CompactTransitionMarker in @('session_id = self.session_id','slot = record.slot','id = record.id','previous = previous','state = next_state','evidence = evidence')) {
    Assert-True ($TransitionContent.Contains($CompactTransitionMarker)) "Compact opponent transition lost identity marker: $CompactTransitionMarker"
}

foreach ($IntegrityMarker in @('VERTICAL_ESCAPE_GRACE_MS', 'EARLY_SELF_DEATH_WINDOW_MS', 'GA_FIGHT_INTEGRITY_FAILED', 'integrity_status', 'vertical_escape', 'early_self_death')) {
    Assert-True ($Task12EntityContent.Contains($IntegrityMarker)) "Arena integrity evidence is missing marker: $IntegrityMarker"
}
foreach ($DiagnosticMarker in @('GA_EARLY_SELF_DEATH_DIAGNOSTIC', 'spawn_position', 'observed_position', 'displacement', 'queries', 'server_available', 'online_available')) {
    Assert-True ($Task12EntityContent.Contains($DiagnosticMarker)) "Early self-death diagnostic is missing marker: $DiagnosticMarker"
}
foreach ($DiagnosticReviewMarker in @('finite_displacement', 'early_self_death_diagnostic_builder', 'self.integrity_fault == nil')) {
    Assert-True ($Task12EntityContent.Contains($DiagnosticReviewMarker)) "Early self-death diagnostic review fix is missing marker: $DiagnosticReviewMarker"
}
Assert-True ($Task12EntityContent.Contains('Diagnostic builder must return a plain table')) 'Early self-death diagnostic builder returns must be plain tables.'
Assert-True ($Task12EntityContent.Contains('VICTORY_DEFEATED_STATES') -and $Task12EntityContent -match 'VICTORY_DEFEATED_STATES\[record\.terminal_state\]') 'Missing opponents must remain non-victory-qualified until integrity recovery starts'
foreach ($IntegrityMarker in @('MAX_INTEGRITY_RETRIES', 'integrity_retry', 'reconcile_active_integrity', 'GA_FIGHT_INTEGRITY_RETRY_EXHAUSTED')) {
    Assert-True ($Task12OrchestratorContent.Contains($IntegrityMarker)) "Arena integrity recovery is missing marker: $IntegrityMarker"
}
Assert-True ($Task12OrchestratorContent -match 'reconcile_active_integrity\s*\([\s\S]{0,500}reconcile_active_victory\s*\(') 'Integrity recovery must be reconciled before victory'
Assert-True ($Task12BootstrapContent.Contains('object_position')) 'Bootstrap must bind guarded opponent position evidence'
$Task13RuntimeTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($RuntimeRegression in @(
    [PSCustomObject]@{ Name = 'runtime_fatal_main_menu_bypasses_terminal_cleanup_error'; Function = 'fatal_main_menu_bypasses_terminal_cleanup_error' },
    [PSCustomObject]@{ Name = 'runtime_ordinary_main_menu_still_rejects_terminal_cleanup_error'; Function = 'ordinary_main_menu_still_rejects_terminal_cleanup_error' },
    [PSCustomObject]@{ Name = 'runtime_entity_wounded_cleanup_holds_offline_before_release'; Function = 'runtime_entity_wounded_cleanup_holds_offline_before_release' },
    [PSCustomObject]@{ Name = 'runtime_entity_living_defeat_cleanup_holds_offline'; Function = 'runtime_entity_living_defeat_cleanup_holds_offline' },
    [PSCustomObject]@{ Name = 'runtime_entity_cleanup_quiesce_failure_is_terminal_without_release'; Function = 'runtime_entity_cleanup_quiesce_failure_is_terminal_without_release' },
    [PSCustomObject]@{ Name = 'runtime_entity_cleanup_quiesce_rejects_lost_npc_tag_before_hold'; Function = 'runtime_entity_cleanup_quiesce_rejects_lost_npc_tag_before_hold' },
    [PSCustomObject]@{ Name = 'runtime_entity_cleanup_quiesce_rejects_reused_npc_id_before_hold'; Function = 'runtime_entity_cleanup_quiesce_rejects_reused_npc_id_before_hold' },
    [PSCustomObject]@{ Name = 'runtime_entity_dead_cleanup_bypasses_offline_hold'; Function = 'runtime_entity_dead_cleanup_bypasses_offline_hold' },
    [PSCustomObject]@{ Name = 'runtime_entity_authoritative_absence_cleanup_bypasses_offline_hold'; Function = 'runtime_entity_authoritative_absence_cleanup_bypasses_offline_hold' }
)) {
    $RuntimeRegistrationPattern = '\{\s*name\s*=\s*"' + [regex]::Escape($RuntimeRegression.Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($RuntimeRegression.Function) + '\s*\}'
    Assert-True ($Task13RuntimeTests -match $RuntimeRegistrationPattern) "Regression case must be registered exactly: $($RuntimeRegression.Name) -> $($RuntimeRegression.Function)."
}
foreach ($IntegrityTest in @('runtime_entity_vertical_escape_requires_grace', 'runtime_entity_missing_is_integrity_not_victory', 'runtime_entity_early_self_death_is_integrity', 'runtime_entity_early_self_death_diagnostic_failures_do_not_suppress_integrity', 'runtime_orchestrator_integrity_retries_same_spec_twice', 'runtime_orchestrator_integrity_retry_exhaustion_fails', 'runtime_entity_cleanup_retires_vanished_owned_child')) {
    Assert-True ($Task13RuntimeTests.Contains($IntegrityTest)) "Runtime integrity suite is missing case: $IntegrityTest"
}

Assert-True ($Task13RuntimeTests.Contains('runtime_entity_post_request_online_failure_requiesces_before_release')) 'Runtime cleanup suite must cover post-side-effect online-request failure'
Assert-True ($Task13RuntimeTests.Contains('runtime_entity_cleanup_error_accumulator_rejects_malformed_and_cyclic_errors')) 'Runtime cleanup suite must cover malformed and cyclic cleanup errors'
Assert-True ($Task13RuntimeTests.Contains('runtime_entity_lifecycle_cleanup_takes_over_stopping')) 'Runtime cleanup suite must cover STOPPING lifecycle takeover'
$Task2DriveOnlineStart = $Task12EntityContent.IndexOf('function EntityAdapter:drive_online')
$Task2DriveOnlineEnd = if ($Task2DriveOnlineStart -ge 0) { $Task12EntityContent.IndexOf('function EntityAdapter:add_cleanup_error', $Task2DriveOnlineStart) } else { -1 }
if ($Task2DriveOnlineStart -ge 0 -and $Task2DriveOnlineEnd -gt $Task2DriveOnlineStart) {
    $Task2DriveOnlineBlock = $Task12EntityContent.Substring($Task2DriveOnlineStart, $Task2DriveOnlineEnd - $Task2DriveOnlineStart)
    Assert-True ($Task2DriveOnlineBlock -match 'record\.held_offline\s*=\s*false[\s\S]{0,300}result_call\("GA_ENTITY_ONLINE_REQUEST_FAILED"') 'Online-request side effects must clear offline authority before request invocation'
}
foreach ($CleanupMarker in @('quiesce_live_owned_npcs', 'GA_ENTITY_CLEANUP_QUIESCE_FAILED', 'cleanup_phase', 'release_index', 'session_id')) {
    Assert-True ($Task12EntityContent.Contains($CleanupMarker)) "Entity cleanup quiescence contract is missing marker: $CleanupMarker"
}
$Task2QuiesceStart = $Task12EntityContent.IndexOf('function EntityAdapter:quiesce_live_owned_npcs')
$Task2QuiesceEnd = if ($Task2QuiesceStart -ge 0) { $Task12EntityContent.IndexOf('function EntityAdapter:quarantine_live_records', $Task2QuiesceStart) } else { -1 }
if ($Task2QuiesceStart -ge 0 -and $Task2QuiesceEnd -gt $Task2QuiesceStart) {
    $Task2QuiesceBlock = $Task12EntityContent.Substring($Task2QuiesceStart, $Task2QuiesceEnd - $Task2QuiesceStart)
    $Task2IdentityProof = $Task2QuiesceBlock.IndexOf('self.record_by_id[record.id] ~= record')
    $Task2TaggedProof = $Task2QuiesceBlock.IndexOf('record.tagged ~= true')
    $Task2OwnerProof = $Task2QuiesceBlock.IndexOf('self:load_owner_tag(record.id)')
    $Task2ServerLookup = $Task2QuiesceBlock.IndexOf('self.deps.server_entity')
    $Task2ExistenceProof = $Task2QuiesceBlock.IndexOf('self:entity_exists(record.id)')
    $Task2ReleasedRetirement = $Task2QuiesceBlock.IndexOf('record.released = true')
    $Task2CleanupAbsent = $Task2QuiesceBlock.IndexOf('cleanup_absent')
    $Task2OfflineHold = $Task2QuiesceBlock.IndexOf('self.deps.hold_offline')
    Assert-True ($Task2IdentityProof -ge 0 -and $Task2TaggedProof -gt $Task2IdentityProof -and $Task2ServerLookup -gt $Task2TaggedProof -and $Task2ExistenceProof -gt $Task2ServerLookup -and $Task2ReleasedRetirement -gt $Task2ExistenceProof -and $Task2CleanupAbsent -gt $Task2ReleasedRetirement -and $Task2OwnerProof -gt $Task2CleanupAbsent -and $Task2OfflineHold -gt $Task2OwnerProof) 'Quiescence must prove internal identity before server lookup, retire authoritative absence before persisted-tag proof, and prove the current owner before offline hold.'
} else {
    Assert-True $false 'Quiescence ownership proof must remain structurally testable.'
}
Assert-True ($Task13RuntimeTests.Contains('accepted fatal disconnect clears fatal UI exactly once across repeated clicks')) 'Accepted repeated fatal clicks must clear fatal UI exactly once.'
$Task4FatalEnterStart = $Task12OrchestratorContent.IndexOf('function Orchestrator:enter_fatal')
$Task4FatalEnterEnd = if ($Task4FatalEnterStart -ge 0) { $Task12OrchestratorContent.IndexOf('function Orchestrator:on_callback_error', $Task4FatalEnterStart) } else { -1 }
if ($Task4FatalEnterStart -ge 0 -and $Task4FatalEnterEnd -gt $Task4FatalEnterStart) {
    $Task4FatalEnterBlock = $Task12OrchestratorContent.Substring($Task4FatalEnterStart, $Task4FatalEnterEnd - $Task4FatalEnterStart)
    Assert-True ($Task4FatalEnterBlock -match 'pcall\s*\(\s*show\s*,\s*errors\s*,\s*function\s*\(\s*\)\s*return\s+self:fatal_main_menu_action\s*\(\s*\)') 'Fatal UI must bind its Main menu action to the fatal-only cleanup-bypass exit.'
} else {
    Assert-True $false 'Fatal entry path must remain structurally testable.'
}
$Task4DriveCleanupStart = $Task12EntityContent.IndexOf('function EntityAdapter:drive_cleanup')
$Task4DriveCleanupEnd = if ($Task4DriveCleanupStart -ge 0) { $Task12EntityContent.IndexOf('function EntityAdapter:fail_and_rollback', $Task4DriveCleanupStart) } else { -1 }
if ($Task4DriveCleanupStart -ge 0 -and $Task4DriveCleanupEnd -gt $Task4DriveCleanupStart) {
    $Task4DriveCleanupBlock = $Task12EntityContent.Substring($Task4DriveCleanupStart, $Task4DriveCleanupEnd - $Task4DriveCleanupStart)
    Assert-True ($Task4DriveCleanupBlock.Contains('self:quiesce_live_owned_npcs()')) 'Entity cleanup must quiesce living owned NPCs before it can submit releases.'
} else {
    Assert-True $false 'Entity cleanup path must remain structurally testable.'
}
$Task2CleanupAccumulatorStart = $Task12EntityContent.IndexOf('function EntityAdapter:add_cleanup_error')
$Task2CleanupAccumulatorEnd = if ($Task2CleanupAccumulatorStart -ge 0) { $Task12EntityContent.IndexOf('function EntityAdapter:quiesce_live_owned_npcs', $Task2CleanupAccumulatorStart) } else { -1 }
if ($Task2CleanupAccumulatorStart -ge 0 -and $Task2CleanupAccumulatorEnd -gt $Task2CleanupAccumulatorStart) {
    $Task2CleanupAccumulatorBlock = $Task12EntityContent.Substring($Task2CleanupAccumulatorStart, $Task2CleanupAccumulatorEnd - $Task2CleanupAccumulatorStart)
    Assert-True ($Task2CleanupAccumulatorBlock.Contains('pcall(copy_plain')) 'Cleanup error accumulation must safely validate copy_plain failures'
}
Assert-True ($Task12BootstrapContent.Contains('snapshot.state ~= "STOPPING"')) 'Lifecycle entity cleanup must treat STOPPING as a retryable pending state'

$Task7CatalogPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$Task7DifficultyPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$Task7StorePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script'
$Task7BootstrapPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script'
$Task7OrchestratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script'
$Task7EnglishTextPath = Join-Path $RepoRoot 'src\gamedata\configs\text\eng\st_gamma_arena.xml'
$Task7RussianTextPath = Join-Path $RepoRoot 'src\gamedata\configs\text\rus\st_gamma_arena.xml'
if ((Test-Path -LiteralPath $Task7CatalogPath) -and (Test-Path -LiteralPath $Task7DifficultyPath)) {
    $Task7CatalogContent = Get-Content -LiteralPath $Task7CatalogPath -Raw
    $Task7DifficultyContent = Get-Content -LiteralPath $Task7DifficultyPath -Raw
    Assert-True ($Task7CatalogContent -match '(?ms)\[meta\].*?schema_version\s*=\s*10\s*.*?revision\s*=\s*11\s*.*?generator_version\s*=\s*11') 'Universal catalog metadata must use schema 10, revision 11, and generator 11.'
    Assert-True ($Task7DifficultyContent -match '(?ms)\[meta\].*?schema_version\s*=\s*4\s*.*?revision\s*=\s*5') 'Weighted player loadouts must retain difficulty schema 4 and revision 5.'
    Assert-True ($Task7DifficultyContent -notmatch '(?m)^player_loadout_budget\s*=') 'Difficulty catalog must expose only separate gear and medical budgets.'
}
if (Test-Path -LiteralPath $Task7BootstrapPath) {
    $Task7BootstrapContent = Get-Content -LiteralPath $Task7BootstrapPath -Raw
    Assert-True ($Task7BootstrapContent -match 'local\s+callback_names\s*=\s*\{[\s\S]{0,600}"actor_on_before_death"[\s\S]{0,160}"actor_on_death"') 'Bootstrap callback registration must retain actor_on_before_death followed by actor_on_death.'
    $Task7ChargeStart = $Task7BootstrapContent.LastIndexOf('if equipment.phase == "CHARGE_OUTFIT" then')
    $Task7ChargeEnd = if ($Task7ChargeStart -ge 0) { $Task7BootstrapContent.IndexOf('equipment.role_index = equipment.role_index + 1', $Task7ChargeStart) } else { -1 }
    Assert-True ($Task7ChargeStart -ge 0 -and $Task7ChargeEnd -gt $Task7ChargeStart) 'Powered-exo CHARGE_OUTFIT phase must remain structurally testable.'
    if ($Task7ChargeStart -ge 0 -and $Task7ChargeEnd -gt $Task7ChargeStart) {
        $Task7ChargeBlock = $Task7BootstrapContent.Substring($Task7ChargeStart, $Task7ChargeEnd - $Task7ChargeStart)
        Assert-True ($Task7ChargeBlock -match 'exo_get_data[\s\S]{0,700}exo_init_data[\s\S]{0,700}exo_set_data[\s\S]{0,500}GA_ACTOR_EXO_VERIFY_FAILED[\s\S]{0,500}exo_get_data[\s\S]{0,500}verified\.value\.power\s*~=\s*100') 'Powered-exo CHARGE_OUTFIT must initialize fresh state, then read back and verify 100-percent charge after writing it.'
    }
}
if (Test-Path -LiteralPath $Task7OrchestratorPath) {
    $Task7OrchestratorContent = Get-Content -LiteralPath $Task7OrchestratorPath -Raw
    $Task7BeforeDeathStart = $Task7OrchestratorContent.IndexOf('function Orchestrator:actor_on_before_death')
    $Task7AfterDeathStart = if ($Task7BeforeDeathStart -ge 0) { $Task7OrchestratorContent.IndexOf('function Orchestrator:actor_on_death', $Task7BeforeDeathStart) } else { -1 }
    Assert-True ($Task7BeforeDeathStart -ge 0 -and $Task7AfterDeathStart -gt $Task7BeforeDeathStart) 'Natural-death callback boundary must remain structurally testable.'
    if ($Task7BeforeDeathStart -ge 0 -and $Task7AfterDeathStart -gt $Task7BeforeDeathStart) {
        $Task7BeforeDeathBlock = $Task7OrchestratorContent.Substring($Task7BeforeDeathStart, $Task7AfterDeathStart - $Task7BeforeDeathStart)
        Assert-True ($Task7BeforeDeathBlock -match 'arm_defeat') 'Natural death must arm a durable defeat intent before engine death.'
        Assert-True ($Task7BeforeDeathBlock -notmatch '\bret_value\s*=\s*(?:false|nil)\b') 'Natural death must not cancel lethal engine damage through flags.ret_value.'
        Assert-True ($Task7BeforeDeathBlock -notmatch 'hold_after_logical_death|release_logical_death_hold') 'Natural death must not invoke logical-death hold or revival behavior.'
    }
    if ($Task7AfterDeathStart -ge 0) {
        $Task7DeathBlock = $Task7OrchestratorContent.Substring($Task7AfterDeathStart)
        Assert-True ($Task7DeathBlock -match 'confirm_defeat[\s\S]{0,1200}neutralize_owned_opponents') 'Real actor death must confirm defeat then neutralize owned opponents.'
    }
}
$Task7DeathControlScripts = @(
    'src\gamedata\scripts\gamma_arena_orchestrator.script',
    'src\gamedata\scripts\gamma_arena_bootstrap.script',
    'src\gamedata\scripts\gamma_arena_actor_adapter.script',
    'src\gamedata\scripts\gamma_arena_main_menu.script'
)
foreach ($Task7DeathControlRelativePath in $Task7DeathControlScripts) {
    $Task7DeathControlPath = Join-Path $RepoRoot $Task7DeathControlRelativePath
    if (Test-Path -LiteralPath $Task7DeathControlPath) {
        $Task7DeathControlContent = Get-Content -LiteralPath $Task7DeathControlPath -Raw
        Assert-True ($Task7DeathControlContent -notmatch '(?i)hold_after_logical_death|release_logical_death_hold|held_after_death|logical[_-]?death|\brevive\b|set_invulnerable|\.invulnerable\b') 'Production Arena death control must not invoke logical-death hold, revival, invulnerability, or healing APIs.'
        if ($Task7DeathControlRelativePath -ne 'src\gamedata\scripts\gamma_arena_actor_adapter.script') {
            Assert-True ($Task7DeathControlContent -notmatch '(?i)\b(?:heal|set_health(?:_ex)?)\s*\(') 'Production Arena death control must not invoke logical-death hold, revival, invulnerability, or healing APIs.'
        }
    }
}
if (Test-Path -LiteralPath $Task7StorePath) {
    $Task7StoreContent = Get-Content -LiteralPath $Task7StorePath -Raw
    Assert-True ($Task7StoreContent -match 'local\s+DEFEAT_TOKEN_TTL\s*=\s*600') 'Defeat intents must retain their 600-second TTL.'
    $Task7TokenStart = $Task7StoreContent.IndexOf('local function parse_defeat_token_impl')
    $Task7TokenEnd = if ($Task7TokenStart -ge 0) { $Task7StoreContent.IndexOf('local function validate_defeat_context', $Task7TokenStart) } else { -1 }
    $Task7ConfirmStart = $Task7StoreContent.IndexOf('function Store:confirm_defeat')
    $Task7ConfirmEnd = if ($Task7ConfirmStart -ge 0) { $Task7StoreContent.IndexOf('function Store:peek_defeat', $Task7ConfirmStart) } else { -1 }
    $Task7PeekStart = $Task7StoreContent.IndexOf('function Store:peek_defeat')
    $Task7PeekEnd = if ($Task7PeekStart -ge 0) { $Task7StoreContent.IndexOf('function Store:consume_defeat', $Task7PeekStart) } else { -1 }
    Assert-True ($Task7TokenStart -ge 0 -and $Task7TokenEnd -gt $Task7TokenStart -and $Task7ConfirmStart -ge 0 -and $Task7ConfirmEnd -gt $Task7ConfirmStart) 'Defeat token validation and confirmation boundaries must remain structurally testable.'
    if ($Task7TokenStart -ge 0 -and $Task7TokenEnd -gt $Task7TokenStart) {
        $Task7TokenBlock = $Task7StoreContent.Substring($Task7TokenStart, $Task7TokenEnd - $Task7TokenStart)
        Assert-True ($Task7TokenBlock -match 'now\s*-\s*issued_at\s*>\s*DEFEAT_TOKEN_TTL') 'Defeat token parsing must enforce the defeat TTL.'
    }
    if ($Task7ConfirmStart -ge 0 -and $Task7ConfirmEnd -gt $Task7ConfirmStart) {
        $Task7ConfirmBlock = $Task7StoreContent.Substring($Task7ConfirmStart, $Task7ConfirmEnd - $Task7ConfirmStart)
        Assert-True ($Task7ConfirmBlock -match 'defeat\.value\.stage\s*==\s*"confirmed"' -and $Task7ConfirmBlock -match '\{\s*"defeat_stage"\s*,\s*"confirmed"\s*\}') 'Defeat confirmation must preserve the confirmed-stage transition and idempotence.'
    }
    Assert-True ($Task7PeekStart -ge 0 -and $Task7PeekEnd -gt $Task7PeekStart) 'Defeat peek boundary must remain structurally testable.'
    if ($Task7PeekStart -ge 0 -and $Task7PeekEnd -gt $Task7PeekStart) {
        $Task7PeekBlock = $Task7StoreContent.Substring($Task7PeekStart, $Task7PeekEnd - $Task7PeekStart)
        Assert-True ($Task7PeekBlock -match 'defeat\.value\.stage\s*~=\s*"confirmed"[\s\S]{0,240}clear_defeat_and_return\s*\(\s*config\s*,\s*gamma_arena_result\.ok\s*\(\s*false\s*\)\s*\)') 'Readable non-confirmed defeat peeks must transactionally clear every defeat key before returning false.'
    }
}
foreach ($Task7TextPath in @($Task7EnglishTextPath, $Task7RussianTextPath)) {
    if (Test-Path -LiteralPath $Task7TextPath) {
        try {
            [xml]$Task7Text = Get-Content -LiteralPath $Task7TextPath -Raw
            Assert-True ($null -ne $Task7Text.SelectSingleNode("//*[local-name()='string' and @id='st_gamma_arena_result_defeat']")) "Defeat localization is missing from $(Get-RelativeRepoPath $Task7TextPath)."
            Assert-True ($null -ne $Task7Text.SelectSingleNode("//*[local-name()='string' and @id='st_gamma_arena_result_new_fight']")) "Fresh-fight localization is missing from $(Get-RelativeRepoPath $Task7TextPath)."
        }
        catch { Assert-True $false "Defeat localization must parse: $(Get-RelativeRepoPath $Task7TextPath)." }
    }
}

$FatalExitOrchestratorContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script') -Raw
$FatalExitBootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
Assert-True ($FatalExitOrchestratorContent -match 'function\s+Orchestrator:submit_disconnect\s*\(') 'Fatal exit must isolate idempotent disconnect submission.'
Assert-True ($FatalExitOrchestratorContent -match 'function\s+Orchestrator:fatal_main_menu_action\s*\(') 'Fatal exit must expose a terminal-only main-menu action.'
Assert-True ($FatalExitOrchestratorContent -match 'function\s+Orchestrator:fatal_main_menu_action\s*\([\s\S]{0,1400}clear_transient') 'Fatal exit must best-effort clear transient intents.'
Assert-True ($FatalExitBootstrapContent -match 'function\s+default_fatal_ui\s*\([\s\S]{0,500}clear_fatal') 'Fatal UI port must expose clear_fatal.'

$FatalExitStart = $FatalExitOrchestratorContent.IndexOf('function Orchestrator:enter_fatal')
$FatalExitEnd = if ($FatalExitStart -ge 0) { $FatalExitOrchestratorContent.IndexOf('function Orchestrator:on_callback_error', $FatalExitStart) } else { -1 }
Assert-True ($FatalExitStart -ge 0 -and $FatalExitEnd -gt $FatalExitStart) 'Fatal routing boundary must remain structurally testable.'
if ($FatalExitStart -ge 0 -and $FatalExitEnd -gt $FatalExitStart) {
    $FatalExitBlock = $FatalExitOrchestratorContent.Substring($FatalExitStart, $FatalExitEnd - $FatalExitStart)
    Assert-True (([regex]::Matches($FatalExitBlock, 'fatal_main_menu_action\s*\(')).Count -ge 2) 'Both fatal UI callback routes must use the fatal-only disconnect action.'
    Assert-True (([regex]::Matches($FatalExitBlock, 'self:main_menu_action\s*\(')).Count -eq 0) 'Fatal UI callback routes must not use ordinary cleanup-gated exit.'
    Assert-True ($FatalExitBlock -notmatch 'errors\s*\[\s*#errors\s*\+\s*1\s*\]\s*=\s*ui_cleanup') 'Fatal UI cleanup errors must use display-level deduplication.'
    Assert-True ($FatalExitBlock -notmatch 'errors\s*\[\s*#errors\s*\+\s*1\s*\]\s*=\s*cleared') 'Fatal transient-clear errors must use display-level deduplication.'
}
Assert-True ($FatalExitOrchestratorContent -match 'show_countdown[\s\S]{0,800}on_main_menu\s*=\s*function\s*\([\s\S]{0,250}request_main_menu_exit') 'Countdown result UI must retain the normal main-menu cleanup route.'
Assert-True ($FatalExitOrchestratorContent -match 'show_result[\s\S]{0,800}on_main_menu\s*=\s*function\s*\([\s\S]{0,250}request_main_menu_exit') 'Result UI must retain the normal main-menu cleanup route.'
Assert-True ($FatalExitOrchestratorContent -match 'function\s+Orchestrator:drive_runtime\s*\([\s\S]{0,900}pending_disconnect[\s\S]{0,300}main_menu_action') 'Normal result cleanup must still submit through main_menu_action.'

$BonusAmmoEntityContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_entity_adapter.script') -Raw
$BonusAmmoBootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
$BonusAmmoRuntimeContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
Assert-True ($BonusAmmoEntityContent -match 'gamma_arena_item_materializer\.descriptors\(actor_spec\.items, catalog\)') 'Entity adapter must preflight universal actor items before mutation.'
$BonusPreflightStart = $BonusAmmoEntityContent.IndexOf('function EntityAdapter:begin_apply')
$BonusPreflightMutation = if ($BonusPreflightStart -ge 0) { $BonusAmmoEntityContent.IndexOf('self:__init(self.deps)', $BonusPreflightStart) } else { -1 }
Assert-True ($BonusPreflightStart -ge 0 -and $BonusPreflightMutation -gt $BonusPreflightStart) 'Bonus ammo static contract must find the entity preflight-before-mutation boundary.'
if ($BonusPreflightStart -ge 0 -and $BonusPreflightMutation -gt $BonusPreflightStart) {
    $BonusPreflightSlice = $BonusAmmoEntityContent.Substring($BonusPreflightStart, $BonusPreflightMutation - $BonusPreflightStart)
    Assert-True (([regex]::Matches($BonusPreflightSlice, 'gamma_arena_item_materializer\.descriptors\(')).Count -ge 2) 'Actor and opponent universal items must resolve through materializer preflight before mutation.'
}
Assert-True ($BonusAmmoBootstrapContent -match 'bonus_ammo_rounds') 'Actor loadout must retain bonus_ammo_rounds in its readiness state.'
Assert-True ($BonusAmmoBootstrapContent -match 'role\s*=\s*"bonus_ammo"') 'Actor loadout must ownership-tag the bonus ammo descriptor role.'
Assert-True ($BonusAmmoBootstrapContent -match 'records_snapshot\s*=\s*function') 'Actor loadout must expose a read-only copied-record snapshot for ownership regression proof.'
Assert-True ($BonusAmmoBootstrapContent -match 'expected_created_quantity\(descriptor, index, #entities, descriptor\.box_size\)') 'Unreadable actor ammo quantities must use each descriptor box_size.'
foreach ($Name in @('runtime_actor_loadout_creates_exact_bonus_ammo_box','runtime_entity_bonus_ammo_box_size_failure_precedes_actor_mutation','runtime_actor_loadout_bonus_ammo_rollback_is_owned')) {
    Assert-True ($BonusAmmoRuntimeContent -match [regex]::Escape($Name)) "Bonus ammo runtime regression must cover $Name"
}

$InventoryDrainActorContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_actor_adapter.script') -Raw
$InventoryDrainBootstrapContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script') -Raw
$InventoryDrainRuntimeContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Marker in @('inventory_drain','last_progress_at','submitted_ids','remaining_ids','poll_count','last_count = 0','inventory_drain_timeout_ms','elapsed_since_progress_ms','total_elapsed_ms','item_section','snapshot_inventory','parent_id_matches_actor','owned_actor_id','requested_actor_id')) {
    Assert-True ($InventoryDrainActorContent -match [regex]::Escape($Marker)) "Actor inventory drain must cover $Marker"
}
foreach ($Marker in @('clock = function() return time_global() end','inventory_drain_timeout_ms = 10000','item_section = function(item) return item:section() end')) {
    Assert-True ($InventoryDrainBootstrapContent -match [regex]::Escape($Marker)) "Bootstrap inventory drain composition must cover $Marker"
}
foreach ($Name in @('runtime_actor_inventory_drain_waits_for_looted_items','runtime_actor_inventory_drain_releases_newly_surfaced_item_once','runtime_actor_inventory_drain_times_out_with_sorted_evidence','runtime_actor_inventory_drain_timeout_is_wrap_safe','runtime_actor_inventory_drain_rejects_unowned_public_actor','runtime_actor_inventory_native_identity_uses_ids','runtime_bootstrap_actor_ownership_is_id_only_and_fail_closed','runtime_actor_inventory_drain_rejects_direct_nil_and_invalid_snapshot_values','runtime_actor_inventory_drain_submits_sorted_deduplicated_ids','runtime_actor_inventory_drain_cleanup_clears_transaction','runtime_wait_inventory_blocks_fight_generation_and_loadout')) {
    Assert-True ($InventoryDrainRuntimeContent -match [regex]::Escape($Name)) "Actor inventory drain runtime regression must cover $Name"
}
foreach ($UnsafeEquality in @(
    '\bparent\s*(?:==|~=)\s*actor\b',
    '\bactor\s*(?:==|~=)\s*parent\b',
    'owned\.value\s*(?:==|~=)\s*actor\b',
    '\bactor\s*(?:==|~=)\s*owned\.value'
)) {
    Assert-True ($InventoryDrainActorContent -notmatch $UnsafeEquality) "Actor inventory ownership must not compare native game_object values: $UnsafeEquality"
}
foreach ($UnsafeEquality in @(
    '\bcandidate\s*(?:==|~=)\s*(?:\(\s*)?db\.actor',
    'db\.actor\s*(?:==|~=)\s*candidate\b',
    '\bcandidate\s*(?:==|~=)\s*current_actor\b',
    '\bcurrent_actor\s*(?:==|~=)\s*candidate\b'
)) {
    Assert-True ($InventoryDrainBootstrapContent -notmatch $UnsafeEquality) "Bootstrap actor ownership must not compare native game_object values: $UnsafeEquality"
}
foreach ($Marker in @('function actor_ownership_matches','runtime_game_object_id','type(method) ~= "function"','id == math.huge','id == -math.huge','return actor_ownership_matches')) {
    Assert-True ($InventoryDrainBootstrapContent -match [regex]::Escape($Marker)) "Bootstrap actor ownership must use strict protected game_object IDs: $Marker"
}
$NativeIdentityRegistration = '\{\s*name\s*=\s*"runtime_actor_inventory_native_identity_uses_ids"\s*,\s*fn\s*=\s*runtime_actor_inventory_native_identity_uses_ids\s*\}'
Assert-True (([regex]::Matches($InventoryDrainRuntimeContent, $NativeIdentityRegistration)).Count -eq 1) 'Regression case must be registered exactly: runtime_actor_inventory_native_identity_uses_ids -> runtime_actor_inventory_native_identity_uses_ids.'
$BootstrapIdentityRegistration = '\{\s*name\s*=\s*"runtime_bootstrap_actor_ownership_is_id_only_and_fail_closed"\s*,\s*fn\s*=\s*runtime_bootstrap_actor_ownership_is_id_only_and_fail_closed\s*\}'
Assert-True (([regex]::Matches($InventoryDrainRuntimeContent, $BootstrapIdentityRegistration)).Count -eq 1) 'Regression case must be registered exactly: runtime_bootstrap_actor_ownership_is_id_only_and_fail_closed -> runtime_bootstrap_actor_ownership_is_id_only_and_fail_closed.'

$RuntimeChildEntityContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_entity_adapter.script') -Raw
$RuntimeChildTestContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($Marker in @('MAX_RUNTIME_CHILDREN','runtime_child_count','adopt_runtime_children','runtime_child','GA_ENTITY_RUNTIME_CHILD_LIMIT','GA_ENTITY_RUNTIME_CHILD_TAG_FAILED','runtime_children')) {
    Assert-True ($RuntimeChildEntityContent -match [regex]::Escape($Marker)) "Runtime NPC child cleanup must cover $Marker"
}
$RuntimeChildDriveStart = $RuntimeChildEntityContent.IndexOf('function EntityAdapter:drive_cleanup')
$RuntimeChildDriveEnd = if ($RuntimeChildDriveStart -ge 0) { $RuntimeChildEntityContent.IndexOf('function EntityAdapter:fail_and_rollback', $RuntimeChildDriveStart) } else { -1 }
$RuntimeChildAdoptionOrdered = $false
if ($RuntimeChildDriveStart -ge 0 -and $RuntimeChildDriveEnd -gt $RuntimeChildDriveStart) {
    $RuntimeChildDrive = $RuntimeChildEntityContent.Substring($RuntimeChildDriveStart, $RuntimeChildDriveEnd - $RuntimeChildDriveStart)
    $RuntimeChildAdoptIndex = $RuntimeChildDrive.IndexOf('self:adopt_cleanup_children()')
    $RuntimeChildReleaseIndex = $RuntimeChildDrive.IndexOf('self:submit_cleanup_wave("npc"')
    $RuntimeChildAdoptionOrdered = $RuntimeChildAdoptIndex -ge 0 -and $RuntimeChildReleaseIndex -gt $RuntimeChildAdoptIndex
}
Assert-True $RuntimeChildAdoptionOrdered 'Entity cleanup must adopt current runtime children before NPC release.'
foreach ($Name in @('runtime_entity_cleanup_adopts_unloaded_weapon_child','runtime_entity_cleanup_adopts_late_child_before_parent','runtime_entity_runtime_child_tag_failure_is_terminal','runtime_entity_runtime_child_limit_is_terminal')) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($RuntimeChildTestContent, $Registration)).Count -eq 1) "Regression case must be registered exactly: $Name -> $Name."
}

$ArenaSaveGuardPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_save_guard.script'
$ArenaDiagnosticsPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_diagnostics.script'
$ArenaWeaponDiagnosticsPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_weapon_diagnostics.script'
$ArenaBootstrapPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script'
$ArenaOrchestratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script'
$ArenaEntityPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
$ArenaRuntimeTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script'
Assert-True (Test-Path -LiteralPath $ArenaSaveGuardPath) 'Arena save guard module is missing.'
Assert-True (Test-Path -LiteralPath $ArenaDiagnosticsPath) 'Arena checkpoint journal module is missing.'
Assert-True (Test-Path -LiteralPath $ArenaWeaponDiagnosticsPath) 'Arena weapon metadata diagnostic module is missing.'
if ((Test-Path -LiteralPath $ArenaSaveGuardPath) -and (Test-Path -LiteralPath $ArenaDiagnosticsPath)) {
    $ArenaSaveGuardContent = Get-Content -LiteralPath $ArenaSaveGuardPath -Raw
    $ArenaDiagnosticsContent = Get-Content -LiteralPath $ArenaDiagnosticsPath -Raw
    foreach ($Marker in @('function SaveGuard:install','function SaveGuard:arm','function SaveGuard:maintain','function SaveGuard:disarm','delay_new_game_autosave','GA_SAVE_COMMAND_SUPPRESSED','GA_SAVE_GUARD_BREACH','token:lower() == "save"')) {
        Assert-True ($ArenaSaveGuardContent -match [regex]::Escape($Marker)) "Arena save guard contract is missing: $Marker"
    }
    foreach ($Marker in @('MAX_LINE_BYTES = 1024','CRITICAL_FIELD_ORDER','weapon_section','function Diagnostics:checkpoint','handle:flush()','handle:close()')) {
        Assert-True ($ArenaDiagnosticsContent -match [regex]::Escape($Marker)) "Arena diagnostics journal contract is missing: $Marker"
    }
    foreach ($ResultName in @('write_result','flush_result','close_result')) {
        Assert-True ($ArenaDiagnosticsContent -match ($ResultName + '\s*==\s*nil')) "Arena diagnostics must reject Lua nil I/O results: $ResultName"
    }
    foreach ($Marker in @('hud_item_visual','GA_DIAGNOSTICS_RECORD_TOO_LARGE','overflow_key')) {
        Assert-True ($ArenaDiagnosticsContent -match [regex]::Escape($Marker)) "Arena diagnostics must fail closed before truncating required metadata: $Marker"
    }
}
if (Test-Path -LiteralPath $ArenaWeaponDiagnosticsPath) {
    $ArenaWeaponDiagnosticsContent = Get-Content -LiteralPath $ArenaWeaponDiagnosticsPath -Raw
    foreach ($Marker in @('function snapshot','unavailable','parent_section','item_visual','anm_show','anm_idle','anm_idle_empty','anm_hide')) {
        Assert-True ($ArenaWeaponDiagnosticsContent -match [regex]::Escape($Marker)) "Arena weapon metadata contract is missing: $Marker"
    }
    Assert-True ($ArenaWeaponDiagnosticsContent -match 'pcall') 'Effective weapon metadata reads must be protected.'
}
$ArenaBootstrapContent = Get-Content -LiteralPath $ArenaBootstrapPath -Raw
$ArenaOrchestratorContent = Get-Content -LiteralPath $ArenaOrchestratorPath -Raw
$ArenaEntityContent = Get-Content -LiteralPath $ArenaEntityPath -Raw
$ArenaRuntimeTestContent = Get-Content -LiteralPath $ArenaRuntimeTestPath -Raw
$ArenaDefaultDiagnosticsStart = $ArenaBootstrapContent.IndexOf('local function default_diagnostics()')
$ArenaDefaultDiagnosticsEnd = if ($ArenaDefaultDiagnosticsStart -ge 0) { $ArenaBootstrapContent.IndexOf('local function default_save_guard', $ArenaDefaultDiagnosticsStart) } else { -1 }
Assert-True ($ArenaDefaultDiagnosticsStart -ge 0 -and $ArenaDefaultDiagnosticsEnd -gt $ArenaDefaultDiagnosticsStart) 'Arena default diagnostics boundary must remain structurally testable.'
if ($ArenaDefaultDiagnosticsStart -ge 0 -and $ArenaDefaultDiagnosticsEnd -gt $ArenaDefaultDiagnosticsStart) {
    $ArenaDefaultDiagnosticsBlock = $ArenaBootstrapContent.Substring($ArenaDefaultDiagnosticsStart, $ArenaDefaultDiagnosticsEnd - $ArenaDefaultDiagnosticsStart)
    $ArenaLevelPresentIndex = $ArenaDefaultDiagnosticsBlock.IndexOf('pcall(level.present)')
    $ArenaLevelNameIndex = $ArenaDefaultDiagnosticsBlock.IndexOf('pcall(level.name)')
    Assert-True ($ArenaDefaultDiagnosticsBlock -match 'type\(level\.present\)\s*~=\s*"function"') 'Arena diagnostics must treat level.present as required engine context.'
    Assert-True ($ArenaLevelPresentIndex -ge 0 -and $ArenaLevelNameIndex -gt $ArenaLevelPresentIndex) 'Arena diagnostics must confirm an active level before querying level.name from the main-menu VM.'
}
$ArenaActorActivationStart = $ArenaBootstrapContent.IndexOf('if equipment.phase == "SUBMIT_ACTIVE" then')
$ArenaActorActivationEnd = if ($ArenaActorActivationStart -ge 0) { $ArenaBootstrapContent.IndexOf('if equipment.phase ~= "WAIT_ACTIVE_VERIFY"', $ArenaActorActivationStart) } else { -1 }
Assert-True ($ArenaActorActivationStart -ge 0 -and $ArenaActorActivationEnd -gt $ArenaActorActivationStart) 'Actor native activation boundary must remain structurally testable.'
if ($ArenaActorActivationStart -ge 0 -and $ArenaActorActivationEnd -gt $ArenaActorActivationStart) {
    $ArenaActorActivationBlock = $ArenaBootstrapContent.Substring($ArenaActorActivationStart, $ArenaActorActivationEnd - $ArenaActorActivationStart)
    $ArenaWeaponCheckpointIndex = $ArenaActorActivationBlock.IndexOf('GA_ACTOR_WEAPON_PRE_ACTIVATE')
    $ArenaMakeActiveIndex = $ArenaActorActivationBlock.IndexOf('ports.make_item_active')
    Assert-True ($ArenaWeaponCheckpointIndex -ge 0 -and $ArenaMakeActiveIndex -gt $ArenaWeaponCheckpointIndex) 'Durable actor weapon evidence must be written before make_item_active.'
    Assert-True ($ArenaActorActivationBlock -match 'GA_ACTOR_WEAPON_CHECKPOINT_FAILED') 'Actor activation must expose structured durable-checkpoint failure.'
}
$ArenaPrepareFightStart = $ArenaOrchestratorContent.IndexOf('function Orchestrator:preflight_fight')
$ArenaPrepareFightEnd = if ($ArenaPrepareFightStart -ge 0) { $ArenaOrchestratorContent.IndexOf('function Orchestrator:begin_countdown_after_equipment', $ArenaPrepareFightStart) } else { -1 }
Assert-True ($ArenaPrepareFightStart -ge 0 -and $ArenaPrepareFightEnd -gt $ArenaPrepareFightStart) 'Fight preparation boundary must remain structurally testable for weapon diagnostics.'
if ($ArenaPrepareFightStart -ge 0 -and $ArenaPrepareFightEnd -gt $ArenaPrepareFightStart) {
    $ArenaPrepareFightBlock = $ArenaOrchestratorContent.Substring($ArenaPrepareFightStart, $ArenaPrepareFightEnd - $ArenaPrepareFightStart)
    $ArenaSelectedWeaponIndex = $ArenaPrepareFightBlock.IndexOf('GA_ACTOR_WEAPON_SELECTED')
    $ArenaBeginApplyIndex = $ArenaPrepareFightBlock.IndexOf('"begin_apply"')
    Assert-True ($ArenaSelectedWeaponIndex -ge 0 -and $ArenaBeginApplyIndex -gt $ArenaSelectedWeaponIndex) 'Selected actor weapon metadata must be logged before entity mutation.'
}
foreach ($Callback in @('"npc_on_before_hit"','"npc_on_hit_callback"')) {
    Assert-True ($ArenaBootstrapContent -match [regex]::Escape($Callback)) "Arena NPC forensic callback is not registered: $Callback"
}
foreach ($Marker in @('FORENSIC_RING_SIZE = 12','FORENSIC_WINDOW_MS = 20000','function EntityAdapter:on_npc_before_hit','function EntityAdapter:on_npc_hit','self_hit_observed','external_hit_observed','health_decay_without_hit','position_or_collision_candidate','unresolved')) {
    Assert-True ($ArenaEntityContent -match [regex]::Escape($Marker)) "Arena NPC forensic contract is missing: $Marker"
}
foreach ($UnsafeMutation in @('hit.power\s*=','hit.impulse\s*=','flags\.[A-Za-z_][A-Za-z0-9_]*\s*=')) {
    Assert-True ($ArenaEntityContent -notmatch $UnsafeMutation) "Arena NPC forensics must not mutate engine hit data: $UnsafeMutation"
}
Assert-True ($ArenaOrchestratorContent -match 'GA_SAVE_GUARD_BREACH') 'Arena save_state must expose native-save breach evidence.'
Assert-True ($Task5StoreContent -match 'function\s+Store:validate_launch_ownership') 'Arena store must expose non-mutating full launch-ownership validation.'
$ArenaRouteValidatorStart = $Task5StoreContent.IndexOf('function Store:validate_launch_activation')
$ArenaRouteValidatorEnd = if ($ArenaRouteValidatorStart -ge 0) { $Task5StoreContent.IndexOf('function Store:consume_launch', $ArenaRouteValidatorStart) } else { -1 }
Assert-True ($ArenaRouteValidatorStart -ge 0 -and $ArenaRouteValidatorEnd -gt $ArenaRouteValidatorStart) 'Arena launch-route validator must remain structurally testable.'
if ($ArenaRouteValidatorStart -ge 0 -and $ArenaRouteValidatorEnd -gt $ArenaRouteValidatorStart) {
    $ArenaRouteValidatorBlock = $Task5StoreContent.Substring($ArenaRouteValidatorStart, $ArenaRouteValidatorEnd - $ArenaRouteValidatorStart)
    Assert-True ($ArenaRouteValidatorBlock -notmatch 'if\s+context\.serialized\s*~=\s*true\s+then\s+return\s+gamma_arena_result\.ok') 'Non-serialized Arena launches must not accept arbitrary current levels.'
    Assert-True ($ArenaRouteValidatorBlock -match '"fake_start"') 'Non-serialized Arena route validation must explicitly own the fake_start handoff.'
}
$ArenaComposeStart = $ArenaBootstrapContent.IndexOf('function compose')
$ArenaComposeEnd = if ($ArenaComposeStart -ge 0) { $ArenaBootstrapContent.IndexOf('local function call_instance', $ArenaComposeStart) } else { -1 }
Assert-True ($ArenaComposeStart -ge 0 -and $ArenaComposeEnd -gt $ArenaComposeStart) 'Arena bootstrap composition boundary must remain structurally testable.'
if ($ArenaComposeStart -ge 0 -and $ArenaComposeEnd -gt $ArenaComposeStart) {
    $ArenaComposeBlock = $ArenaBootstrapContent.Substring($ArenaComposeStart, $ArenaComposeEnd - $ArenaComposeStart)
    Assert-True ($ArenaComposeBlock -notmatch 'save_guard\s*:\s*install') 'Arena bootstrap must not install the global save guard before MCM starts the new game.'
    Assert-True ($ArenaComposeBlock -notmatch 'deps\.current_level') 'Arena bootstrap composition must not query level engine state while the main menu owns the VM.'
    Assert-True ($ArenaComposeBlock -notmatch 'diagnostics\s*:\s*checkpoint') 'Arena bootstrap composition must not perform diagnostic file I/O while the main menu owns the VM.'
}
$ArenaArmGuardStart = $ArenaOrchestratorContent.IndexOf('function Orchestrator:arm_save_guard')
$ArenaArmGuardEnd = if ($ArenaArmGuardStart -ge 0) { $ArenaOrchestratorContent.IndexOf('function Orchestrator:maintain_save_guard', $ArenaArmGuardStart) } else { -1 }
Assert-True ($ArenaArmGuardStart -ge 0 -and $ArenaArmGuardEnd -gt $ArenaArmGuardStart) 'Arena save-guard activation boundary must remain structurally testable.'
if ($ArenaArmGuardStart -ge 0 -and $ArenaArmGuardEnd -gt $ArenaArmGuardStart) {
    $ArenaArmGuardBlock = $ArenaOrchestratorContent.Substring($ArenaArmGuardStart, $ArenaArmGuardEnd - $ArenaArmGuardStart)
    $ArenaInstallIndex = $ArenaArmGuardBlock.IndexOf('"install"')
    $ArenaArmMethodIndex = $ArenaArmGuardBlock.IndexOf('"arm"')
    Assert-True ($ArenaInstallIndex -ge 0 -and $ArenaArmMethodIndex -gt $ArenaInstallIndex) 'Arena launch acceptance must install save suppression immediately before arming it.'
}
$ArenaGuardedStart = $ArenaBootstrapContent.IndexOf('local guarded_callbacks = {')
$ArenaGuardedEnd = if ($ArenaGuardedStart -ge 0) { $ArenaBootstrapContent.IndexOf('}', $ArenaGuardedStart) } else { -1 }
Assert-True ($ArenaGuardedStart -ge 0 -and $ArenaGuardedEnd -gt $ArenaGuardedStart) 'Arena guarded callback table must remain structurally testable.'
if ($ArenaGuardedStart -ge 0 -and $ArenaGuardedEnd -gt $ArenaGuardedStart) {
    $ArenaGuardedBlock = $ArenaBootstrapContent.Substring($ArenaGuardedStart, $ArenaGuardedEnd - $ArenaGuardedStart)
    Assert-True ($ArenaGuardedBlock -notmatch '\bsave_state\s*=') 'save_state must reach the guard-aware orchestrator before ACTIVE to diagnose native saves.'
}
Assert-True ($ArenaBootstrapContent -match 'elseif\s+name\s*==\s*"save_state"[\s\S]{0,900}if\s+not\s+armed\s+then\s+return\s+end') 'Campaign save_state callback must preserve its historical nil return while still reaching guard-aware breach detection.'
$ArenaSaveStateStart = $ArenaOrchestratorContent.IndexOf('function Orchestrator:save_state')
$ArenaSaveStateEnd = if ($ArenaSaveStateStart -ge 0) { $ArenaOrchestratorContent.IndexOf('function Orchestrator:create_session', $ArenaSaveStateStart) } else { -1 }
Assert-True ($ArenaSaveStateStart -ge 0 -and $ArenaSaveStateEnd -gt $ArenaSaveStateStart) 'Arena save_state boundary must remain structurally testable.'
if ($ArenaSaveStateStart -ge 0 -and $ArenaSaveStateEnd -gt $ArenaSaveStateStart) {
    $ArenaSaveStateBlock = $ArenaOrchestratorContent.Substring($ArenaSaveStateStart, $ArenaSaveStateEnd - $ArenaSaveStateStart)
    Assert-True ($ArenaSaveStateBlock -match 'GA_SAVE_GUARD_BREACH') 'Arena save_state must record a guard breach.'
    Assert-True ($ArenaSaveStateBlock -notmatch 'mdata\s*\.\s*gamma_arena_session\s*=') 'Arena save_state must never serialize session data.'
}
$ArenaActivateStart = $ArenaOrchestratorContent.IndexOf('function Orchestrator:activate_once')
$ArenaActivateEnd = if ($ArenaActivateStart -ge 0) { $ArenaOrchestratorContent.IndexOf('function Orchestrator:layout_snapshot', $ArenaActivateStart) } else { -1 }
Assert-True ($ArenaActivateStart -ge 0 -and $ArenaActivateEnd -gt $ArenaActivateStart) 'Arena activation boundary must remain structurally testable.'
if ($ArenaActivateStart -ge 0 -and $ArenaActivateEnd -gt $ArenaActivateStart) {
    $ArenaActivateBlock = $ArenaOrchestratorContent.Substring($ArenaActivateStart, $ArenaActivateEnd - $ArenaActivateStart)
    $ArenaRouteValidationIndex = $ArenaActivateBlock.IndexOf('validate_launch_activation')
    $ArenaOwnershipIndex = $ArenaActivateBlock.IndexOf('validate_launch_ownership')
    $ArenaArmIndex = $ArenaActivateBlock.IndexOf('self:arm_save_guard')
    $ArenaDeferIndex = $ArenaActivateBlock.IndexOf('mark_launch_deferred')
    Assert-True ($ArenaRouteValidationIndex -ge 0 -and $ArenaOwnershipIndex -gt $ArenaRouteValidationIndex) 'Arena route proof must be validated before full launch ownership.'
    Assert-True ($ArenaOwnershipIndex -ge 0 -and $ArenaArmIndex -gt $ArenaOwnershipIndex) 'Arena save suppression must begin only after complete launch ownership validation.'
    Assert-True ($ArenaActivateBlock -notmatch 'enter_fatal\s*\(\s*activation\s*,\s*true') 'Rejected non-mutating launch route proof must be cleared by common fatal routing.'
    Assert-True ($ArenaActivateBlock -notmatch 'enter_fatal\s*\(\s*ownership\s*,\s*true') 'Rejected non-mutating launch ownership must be cleared by common fatal routing.'
    Assert-True ($ArenaArmIndex -ge 0 -and $ArenaDeferIndex -gt $ArenaArmIndex) 'Deferred fake_start launch must arm save suppression before handoff.'
}
$ArenaPrepareFightStart = $ArenaOrchestratorContent.IndexOf('function Orchestrator:preflight_fight')
$ArenaPrepareFightEnd = if ($ArenaPrepareFightStart -ge 0) { $ArenaOrchestratorContent.IndexOf('function Orchestrator:begin_countdown_after_equipment', $ArenaPrepareFightStart) } else { -1 }
Assert-True ($ArenaPrepareFightStart -ge 0 -and $ArenaPrepareFightEnd -gt $ArenaPrepareFightStart) 'Arena prepare_fight boundary must remain structurally testable.'
if ($ArenaPrepareFightStart -ge 0 -and $ArenaPrepareFightEnd -gt $ArenaPrepareFightStart) {
    $ArenaPrepareFightBlock = $ArenaOrchestratorContent.Substring($ArenaPrepareFightStart, $ArenaPrepareFightEnd - $ArenaPrepareFightStart)
    Assert-True ($ArenaPrepareFightBlock -match 'safe_value_call\s*\(\s*"GA_ENTITY_SPEC_INVALID"\s*,\s*spec\.actor\s*\)') 'FightSpec actor accessor must accept its plain participant value.'
    Assert-True ($ArenaPrepareFightBlock -notmatch 'safe_result_call\s*\(\s*"GA_ENTITY_SPEC_INVALID"\s*,\s*spec\.actor\s*\)') 'FightSpec actor accessor must not require a Result wrapper.'
}
$Task8ValidatedSpecStart = $ArenaRuntimeTestContent.IndexOf('local function task8_validated_spec')
$Task8ValidatedSpecEnd = if ($Task8ValidatedSpecStart -ge 0) { $ArenaRuntimeTestContent.IndexOf('local function task8_environment', $Task8ValidatedSpecStart) } else { -1 }
Assert-True ($Task8ValidatedSpecStart -ge 0 -and $Task8ValidatedSpecEnd -gt $Task8ValidatedSpecStart) 'Task 8 FightSpec fixture must remain structurally testable.'
if ($Task8ValidatedSpecStart -ge 0 -and $Task8ValidatedSpecEnd -gt $Task8ValidatedSpecStart) {
    $Task8ValidatedSpecBlock = $ArenaRuntimeTestContent.Substring($Task8ValidatedSpecStart, $Task8ValidatedSpecEnd - $Task8ValidatedSpecStart)
    Assert-True ($Task8ValidatedSpecBlock -match 'actor\s*=\s*function\s*\(\s*\)\s*return\s+clone\s*\(\s*private\.actor\s*\)\s*end') 'Selected-weapon diagnostic regression must exercise a plain FightSpec actor table accessor.'
}
foreach ($Name in @('runtime_save_guard_installs_only_after_launch_ownership','runtime_save_guard_failures_block_launch_mutation','runtime_save_guard_suppresses_only_owned_save_commands','runtime_diagnostics_checkpoint_is_bounded_flushed_and_closed','runtime_diagnostics_checkpoint_rejects_nil_io_results','runtime_diagnostics_checkpoint_rejects_oversized_required_metadata','runtime_weapon_diagnostics_reads_effective_hud_metadata','runtime_weapon_diagnostics_missing_reads_are_unavailable','runtime_actor_weapon_checkpoint_precedes_native_activation','runtime_actor_weapon_checkpoint_failure_blocks_and_rolls_back','runtime_actor_weapon_selected_diagnostic_precedes_entity_mutation','runtime_entity_forensics_are_bounded_non_mutating_and_classified')) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($ArenaRuntimeTestContent, $Registration)).Count -eq 1) "Regression case must be registered exactly: $Name -> $Name."
}

$AudioPath = Join-Path $SourceGamedata 'scripts\gamma_arena_audio.script'
$McmPath = Join-Path $SourceGamedata 'scripts\gamma_arena_mcm.script'
$AudioTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_audio.script'
Assert-True (Test-Path -LiteralPath $AudioPath) 'Arena audio controller must be packaged.'
Assert-True (Test-Path -LiteralPath $McmPath) 'Arena MCM page must be packaged.'
Assert-True (Test-Path -LiteralPath $AudioTestPath) 'Arena audio behavioral contract is missing.'
Assert-True ($ArenaRuntimeTestContent -ne $null) 'Arena runtime test fixture must remain readable.'
if (Test-Path -LiteralPath $AudioPath) {
    $AudioContent = Get-Content -LiteralPath $AudioPath -Raw
    foreach ($Channel in @('crowd','reaction','commentator')) {
        Assert-True ($AudioContent -match ('["'']' + [regex]::Escape($Channel) + '["'']')) "Arena audio must own the $Channel channel."
    }
    foreach ($Resource in @(
        'ambient\\arena\\crowd_1',
        'ambient\\arena\\crowd_2',
        'ambient\\arena\\crowd_3',
        'ambient\\arena\\crowd_wave_1',
        'ambient\\arena\\crowd_wave_2',
        'ambient\\arena\\crowd_wave_3',
        'characters_voice\\scenario\\bar\\arena_megafon\\mega_arena_start',
        'characters_voice\\scenario\\bar\\arena_megafon\\mega_arena_win_1',
        'characters_voice\\scenario\\bar\\arena_megafon\\mega_arena_dead'
    )) {
        Assert-True ($AudioContent.Contains($Resource)) "Arena audio resource is missing: $Resource"
    }
    Assert-True ($AudioContent -notmatch '\bbar_arena_fight') 'Arena audio must not mutate stock Arena fight info portions.'
    Assert-True ($AudioContent -notmatch '\bmath\.random(seed)?\b') 'Arena audio must not consume non-deterministic or gameplay RNG.'
    Assert-True ($AudioContent -match 'return\s+\(integer\s*%\s*3\)\s*\+\s*1') 'Arena audio clip rotation must map zero-based fight_index 0 to clip 1.'
}
if (Test-Path -LiteralPath $McmPath) {
    $McmContent = Get-Content -LiteralPath $McmPath -Raw
    Assert-True ($McmContent -match '["'']gamma_arena/commentator["'']') 'Arena MCM must read the commentator option.'
    Assert-True ($McmContent -match '["'']gamma_arena/crowd_reactions["'']') 'Arena MCM must read the crowd reactions option.'
    Assert-True (([regex]::Matches($McmContent, 'type\s*=\s*["'']check["'']')).Count -eq 2) 'Arena MCM must expose exactly two check controls.'
    Assert-True (([regex]::Matches($McmContent, 'def\s*=\s*true')).Count -eq 2) 'Arena MCM checks must both default to true.'
    Assert-True ($McmContent -notmatch '\bbar_arena_fight') 'Arena MCM must not mutate stock Arena fight info portions.'
}
$McmEnglishPath = Join-Path $SourceGamedata 'configs\text\eng\st_gamma_arena_mcm.xml'
$McmRussianPath = Join-Path $SourceGamedata 'configs\text\rus\st_gamma_arena_mcm.xml'
Assert-True (Test-Path -LiteralPath $McmEnglishPath) 'Arena MCM English localization must be packaged.'
Assert-True (Test-Path -LiteralPath $McmRussianPath) 'Arena MCM Russian localization must be packaged.'
if ((Test-Path -LiteralPath $McmEnglishPath) -and (Test-Path -LiteralPath $McmRussianPath)) {
    $McmEnglishContent = Get-Content -LiteralPath $McmEnglishPath -Raw -Encoding UTF8
    $McmRussianBytes = [IO.File]::ReadAllBytes($McmRussianPath)
    Assert-True (($McmRussianBytes | Where-Object { $_ -gt 127 }).Count -eq 0) 'Arena MCM Russian localization source must remain ASCII-safe Windows-1251 XML.'
    $McmRussianContent = [Text.Encoding]::GetEncoding(1251).GetString($McmRussianBytes)
    Assert-True ($McmRussianContent -match 'encoding="windows-1251"') 'Arena MCM Russian localization must declare the Anomaly/GAMMA Windows-1251 encoding.'
    [xml]$McmRussianXml = $McmRussianContent
    foreach ($StringId in @(
        'ui_mcm_menu_gamma_arena',
        'ui_mcm_gamma_arena_title',
        'ui_mcm_gamma_arena_commentator',
        'ui_mcm_gamma_arena_commentator_desc',
        'ui_mcm_gamma_arena_crowd_reactions',
        'ui_mcm_gamma_arena_crowd_reactions_desc'
    )) {
        Assert-True ($McmEnglishContent -match ('id="' + [regex]::Escape($StringId) + '"')) "Arena MCM English localization is missing: $StringId"
        Assert-True ($McmRussianContent -match ('id="' + [regex]::Escape($StringId) + '"')) "Arena MCM Russian localization is missing: $StringId"
    }
    Assert-True ($McmEnglishContent -match '<text>Commentator</text>') 'Arena MCM English commentator label must be exact.'
    Assert-True ($McmEnglishContent -match '<text>Crowd reactions</text>') 'Arena MCM English crowd label must be exact.'
    $ExpectedRussianCommentator = -join @([char]0x041A,[char]0x043E,[char]0x043C,[char]0x043C,[char]0x0435,[char]0x043D,[char]0x0442,[char]0x0430,[char]0x0442,[char]0x043E,[char]0x0440)
    $ExpectedRussianCrowd = -join @([char]0x0420,[char]0x0435,[char]0x0430,[char]0x043A,[char]0x0446,[char]0x0438,[char]0x0438,[char]0x0020,[char]0x0442,[char]0x043E,[char]0x043B,[char]0x043F,[char]0x044B)
    $RussianCommentatorNode = $McmRussianXml.SelectSingleNode('//string[@id="ui_mcm_gamma_arena_commentator"]/text')
    $RussianCrowdNode = $McmRussianXml.SelectSingleNode('//string[@id="ui_mcm_gamma_arena_crowd_reactions"]/text')
    Assert-True ($null -ne $RussianCommentatorNode -and $RussianCommentatorNode.InnerText -ceq $ExpectedRussianCommentator) 'Arena MCM Russian commentator label must be exact.'
    Assert-True ($null -ne $RussianCrowdNode -and $RussianCrowdNode.InnerText -ceq $ExpectedRussianCrowd) 'Arena MCM Russian crowd label must be exact.'
}
if (Test-Path -LiteralPath $AudioTestPath) {
    $AudioTestContent = Get-Content -LiteralPath $AudioTestPath -Raw
    foreach ($CaseName in @(
        'audio_enabled_start_uses_owned_channels',
        'audio_settings_disable_channel_families_independently',
        'audio_accepted_deaths_rotate_reactions',
        'audio_ambience_advances_without_duplicate_update',
        'audio_live_settings_stop_and_resume_only_ambience',
        'audio_live_disable_retries_one_shot_stop_failure',
        'audio_terminal_events_stop_crowd_and_announce',
        'audio_stop_all_is_idempotent_and_aggregates_failures',
        'audio_settings_failures_are_structured',
        'audio_mcm_defaults_and_boolean_values_are_safe'
    )) {
        $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($CaseName) + '"\s*,\s*fn\s*=\s*[A-Za-z_][A-Za-z0-9_]*\s*\}'
        Assert-True (([regex]::Matches($AudioTestContent, $Registration)).Count -eq 1) "Arena audio contract must register exactly one case: $CaseName"
    }
}
$AudioDomainContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_domain.script') -Raw
Assert-True ($AudioDomainContent -match 'gamma_arena_test_audio\.run\s*\(\s*run_case_fn\s*\)') 'Arena audio tests must run from the Dev domain suite.'
$PackagedSoundAssets = @($AllSourceFiles | Where-Object { $_.Extension -ieq '.ogg' })
Assert-True ($PackagedSoundAssets.Count -eq 0) 'Gamma Arena must reuse effective VFS audio resources instead of packaging OGG files.'
foreach ($Marker in @('gamma_arena_audio.new','sound_object','sound_object.s3d','play_at_pos','overrides.audio','gamma_arena_mcm.snapshot')) {
    Assert-True ($ArenaBootstrapContent -match [regex]::Escape($Marker)) "Bootstrap Arena audio port must cover: $Marker"
}
$AudioStopPortStart = $ArenaBootstrapContent.IndexOf('local function stop_channel(channel)')
$AudioStopPortEnd = if ($AudioStopPortStart -ge 0) { $ArenaBootstrapContent.IndexOf('local function sound_for(path)', $AudioStopPortStart) } else { -1 }
Assert-True ($AudioStopPortStart -ge 0 -and $AudioStopPortEnd -gt $AudioStopPortStart) 'Bootstrap Arena audio stop port must remain structurally testable.'
if ($AudioStopPortStart -ge 0 -and $AudioStopPortEnd -gt $AudioStopPortStart) {
    $AudioStopPortBlock = $ArenaBootstrapContent.Substring($AudioStopPortStart, $AudioStopPortEnd - $AudioStopPortStart)
    $AudioStopCallIndex = $AudioStopPortBlock.IndexOf('handle:stop()')
    $AudioStopClearIndex = $AudioStopPortBlock.IndexOf('active[channel] = nil')
    Assert-True ($AudioStopCallIndex -ge 0 -and $AudioStopClearIndex -gt $AudioStopCallIndex) 'Arena audio stop failure must retain its owned handle for a later cleanup retry.'
}
$AudioPlayingPortStart = $ArenaBootstrapContent.IndexOf('playing = function(channel)')
$AudioPlayingPortEnd = if ($AudioPlayingPortStart -ge 0) { $ArenaBootstrapContent.IndexOf('stop = stop_channel', $AudioPlayingPortStart) } else { -1 }
Assert-True ($AudioPlayingPortStart -ge 0 -and $AudioPlayingPortEnd -gt $AudioPlayingPortStart) 'Bootstrap Arena audio playing port must remain structurally testable.'
if ($AudioPlayingPortStart -ge 0 -and $AudioPlayingPortEnd -gt $AudioPlayingPortStart) {
    $AudioPlayingPortBlock = $ArenaBootstrapContent.Substring($AudioPlayingPortStart, $AudioPlayingPortEnd - $AudioPlayingPortStart)
    Assert-True ($AudioPlayingPortBlock -match 'if\s+not\s+called\s+then\s*return\s+gamma_arena_result\.err') 'Arena audio playing-state failure must retain its owned handle for teardown.'
}
$GitAttributesContent = Get-Content -LiteralPath (Join-Path $RepoRoot '.gitattributes') -Raw
Assert-True ($GitAttributesContent -match '(?m)^src/gamedata/configs/text/rus/st_gamma_arena_mcm\.xml\s+-text\s*$') 'Git must preserve Arena MCM Russian localization bytes without text conversion.'
foreach ($Marker in @('function Orchestrator:audio_event','"begin_fight"','"update"','"opponent_defeated"','"victory"','"defeat"','"stop_all"','GA_AUDIO_EVENT_FAILED')) {
    Assert-True ($ArenaOrchestratorContent -match [regex]::Escape($Marker)) "Orchestrator Arena audio lifecycle must cover: $Marker"
}
foreach ($Name in @('runtime_audio_events_follow_owned_lifecycle','runtime_audio_manual_restart_stops_channels','runtime_audio_cleanup_covers_exit_boundaries','runtime_audio_failures_are_diagnostic_only','runtime_audio_defeat_failure_never_cancels_death')) {
    $Registration = '\{\s*name\s*=\s*"' + [regex]::Escape($Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($Name) + '\s*\}'
    Assert-True (([regex]::Matches($ArenaRuntimeTestContent, $Registration)).Count -eq 1) "Arena audio runtime case must be registered exactly: $Name -> $Name"
}
$ArenaRestartStart = $ArenaOrchestratorContent.IndexOf('function Orchestrator:restart_arena_action')
$ArenaRestartEnd = if ($ArenaRestartStart -ge 0) { $ArenaOrchestratorContent.IndexOf('function Orchestrator:request_main_menu_exit', $ArenaRestartStart) } else { -1 }
Assert-True ($ArenaRestartStart -ge 0 -and $ArenaRestartEnd -gt $ArenaRestartStart) 'Arena manual restart boundary must remain structurally testable for audio cleanup.'
if ($ArenaRestartStart -ge 0 -and $ArenaRestartEnd -gt $ArenaRestartStart) {
    $ArenaRestartBlock = $ArenaOrchestratorContent.Substring($ArenaRestartStart, $ArenaRestartEnd - $ArenaRestartStart)
    Assert-True ($ArenaRestartBlock -match 'audio_event\s*\(\s*"stop_all"') 'Arena manual restart must stop every owned audio channel before cleanup.'
}

$RosterRefreshModel = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_setup_model.script') -Raw
$RosterRefreshPresenter = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_custom_setup_presenter.script') -Raw
$RosterRefreshUi = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_ui_custom.script') -Raw
$RosterRefreshRuntime = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
Assert-True ($RosterRefreshModel -match 'function\s+Model:status_snapshot') 'Custom roster refresh model must expose status_snapshot.'
$DerivedStatusBlock = [regex]::Match($RosterRefreshModel, '(?ms)^function\s+Model:status_snapshot\(\).*?^end\s*$').Value
$DerivedSnapshotBlock = [regex]::Match($RosterRefreshModel, '(?ms)^function\s+Model:snapshot\(\).*?^end\s*$').Value
foreach ($Block in @($DerivedStatusBlock, $DerivedSnapshotBlock)) {
    Assert-True ($Block -match 'deep_copy\(self\.current_validation\)') `
        'Custom snapshots must read the committed validation Result.'
    Assert-True ($Block -match 'derived_values\(self\)') `
        'Custom snapshots must read committed budget and totals Results.'
    Assert-True ($Block -notmatch 'gamma_arena_custom_config\.(?:validate|budget|totals)\s*\(') `
        'Custom snapshots must not repeat public validation, budget, or totals work.'
}
$DerivedRuntimeCase = [regex]::Match($RosterRefreshRuntime,
    '(?ms)^local\s+function\s+runtime_custom_model_status_snapshot_matches_full_status\(\).*?^end\s*$').Value
Assert-True ($DerivedRuntimeCase -match 'set_rank\s*\(\s*2\s*,\s*"novice"\s*\)' -and
    ([regex]::Matches($DerivedRuntimeCase, 'GA_CUSTOM_OVERSPEND')).Count -ge 2) `
    'Custom runtime parity must preserve an overbudget loadout after lowering rank.'
Assert-True ($RosterRefreshPresenter -match 'function\s+Presenter:refresh_status') 'Custom roster refresh presenter must expose refresh_status.'
Assert-True ($RosterRefreshPresenter -match 'function\s+Presenter:refresh_affordability') 'Custom roster refresh presenter must expose arithmetic affordability refresh.'
Assert-True ($RosterRefreshPresenter -match 'local\s+function\s+valid_status_snapshot') 'Custom status refresh must validate snapshot shape before mutation.'
$StatusShapeBlock = [regex]::Match($RosterRefreshPresenter, '(?ms)^local\s+function\s+valid_status_snapshot\(.*?^end\s*$').Value
Assert-True ($StatusShapeBlock -match 'snapshot\.count\s*>\s*snapshot\.capacity') `
    'Custom status refresh must reject a count above authoritative capacity.'
Assert-True ($StatusShapeBlock -match 'snapshot\.capacity\s*>\s*MAX_ROSTER_ROWS') `
    'Custom status refresh must reject capacity above the fixed roster controls.'
$StatusResultBlock = [regex]::Match($RosterRefreshPresenter, '(?ms)^local\s+function\s+valid_result_shape\(.*?^end\s*$').Value
Assert-True ($StatusResultBlock -match 'type\(result\.ok\)\s*~=\s*"boolean"') `
    'Custom status validation must require a boolean Result ok field.'
foreach ($Field in @('code','message','context')) {
    Assert-True ($StatusResultBlock -match ('detail\.' + $Field)) `
        "Failed Custom status validation must require structured error $Field."
}
Assert-True ($StatusShapeBlock -match 'valid_result_shape\s*\(\s*snapshot\.validation\s*\)') `
    'Custom status refresh must validate the full validation Result shape.'
Assert-True ($StatusShapeBlock -match 'snapshot\.can_start\s*~=\s*snapshot\.validation\.ok') `
    'Custom status refresh must require can_start to equal validation.ok exactly.'
Assert-True ($RosterRefreshUi -notmatch 'function\s+refresh_catalog_cells') 'Custom status refresh must not expose a current-page preview helper.'
Assert-True ($RosterRefreshUi -match 'function\s+refresh_inventory_cells') 'Custom status refresh must expose in-place inventory helper.'
$RefreshPresenterStart = $RosterRefreshPresenter.IndexOf('function Presenter:refresh_status(model, view)')
$RefreshPresenterEnd = if ($RefreshPresenterStart -ge 0) { $RosterRefreshPresenter.IndexOf('function status_presentation', $RefreshPresenterStart) } else { -1 }
Assert-True ($RefreshPresenterStart -ge 0 -and $RefreshPresenterEnd -gt $RefreshPresenterStart) 'Custom status refresh presenter must remain structurally testable.'
if ($RefreshPresenterStart -ge 0 -and $RefreshPresenterEnd -gt $RefreshPresenterStart) {
    $RefreshPresenterBlock = $RosterRefreshPresenter.Substring($RefreshPresenterStart, $RefreshPresenterEnd - $RefreshPresenterStart)
    Assert-True ($RefreshPresenterBlock -match 'view\.infrastructure_error_code\s*=\s*nil') `
        'Successful Custom status refresh must clear transient infrastructure status.'
}
$CatalogProjectionStart = $RosterRefreshPresenter.IndexOf('function Presenter:project(model, state)')
$CatalogProjectionEnd = if ($CatalogProjectionStart -ge 0) { $RosterRefreshPresenter.IndexOf('function Presenter:refresh_status', $CatalogProjectionStart) } else { -1 }
Assert-True ($CatalogProjectionStart -ge 0 -and $CatalogProjectionEnd -gt $CatalogProjectionStart) 'Custom catalog projection must remain structurally testable.'
if ($CatalogProjectionStart -ge 0 -and $CatalogProjectionEnd -gt $CatalogProjectionStart) {
    $CatalogProjectionBlock = $RosterRefreshPresenter.Substring($CatalogProjectionStart, $CatalogProjectionEnd - $CatalogProjectionStart)
    Assert-True ($CatalogProjectionBlock -match 'hard_disabled_reason') `
        'Custom catalog projection must preserve an independent hard affordability block.'
    Assert-True ($CatalogProjectionBlock -match 'hard_disabled_context') `
        'Custom catalog projection must preserve hard-block context for later arithmetic refresh.'
}
$CatalogRowsBlock = [regex]::Match($RosterRefreshPresenter, '(?ms)^local\s+function\s+collect_rows\(.*?^end\s*$').Value
Assert-True ($DerivedSnapshotBlock -match 'carry_bonus_mg\s*=\s*definition\.carry_bonus_mg') `
    'Full model snapshot must carry authoritative outfit carry bonus metadata.'
Assert-True ($CatalogRowsBlock -match 'carry_bonus_mg\s*=\s*tonumber\(cell\.carry_bonus_mg\)') `
    'Full presenter projection must retain candidate outfit carry bonus metadata.'
$ProjectedWeightBlock = [regex]::Match($RosterRefreshPresenter,
    '(?ms)^local\s+function\s+projected_weight_hard_block\(.*?^end\s*$').Value
foreach ($Marker in @('cell\.category\s*==\s*"outfit"', 'cell\.carry_bonus_mg', 'projected_weight_limit_mg')) {
    Assert-True ($ProjectedWeightBlock -match $Marker) "Projected weight hard block is missing: $Marker"
}
Assert-True ($CatalogProjectionBlock -match 'snapshot_has_outfit\s*\(\s*snapshot\s*\)' -and
    $CatalogProjectionBlock -match 'projected_weight_hard_block\s*\(\s*snapshot\s*,\s*cell\s*,\s*has_outfit\s*\)') `
    'Full projection must apply candidate effective carry limits from one outfit-state scan.'
$AffordabilityRuntimeBlock = [regex]::Match($RosterRefreshRuntime,
    '(?ms)^local\s+function\s+runtime_custom_presenter_refreshes_affordability_without_model_preview\(\).*?^end\s*$').Value
foreach ($Marker in @('weight_mg\s*=\s*49000', 'weight_limit_mg\s*=\s*50000', 'weight_mg\s*=\s*5000',
    'carry_bonus_mg\s*=\s*10000', '54000/60000')) {
    Assert-True ($AffordabilityRuntimeBlock -match $Marker) "Carry-bonus projection regression is missing: $Marker"
}
$MalformedStatusRuntimeBlock = [regex]::Match($RosterRefreshRuntime,
    '(?ms)^local\s+function\s+runtime_custom_presenter_rejects_malformed_status_snapshots_atomically\(\).*?^end\s*$').Value
foreach ($Marker in @('validation missing ok', 'failed validation missing error', 'failed validation missing error code',
    'failed validation missing error message', 'failed validation missing error context', 'failed validation claims start',
    'successful validation denies start')) {
    Assert-True ($MalformedStatusRuntimeBlock -match [regex]::Escape($Marker)) `
        "Malformed status runtime regression is missing: $Marker"
}
foreach ($HandlerName in @('OnCount', 'OnRank')) {
    $HandlerBlock = [regex]::Match($RosterRefreshUi, ('(?ms)^function\s+UICustom:' + $HandlerName + '\(.*?^end\s*$')).Value
    Assert-True ($HandlerBlock -match 'self:RefreshRosterStatus\(') "Custom $HandlerName must use incremental roster refresh."
    Assert-True ($HandlerBlock -match 'local\s+result\s*=') "Custom $HandlerName must consume its model command Result."
    Assert-True ($HandlerBlock -match 'not\s+result\.ok') "Custom $HandlerName must preserve a rejected command Result."
    foreach ($Forbidden in @('self:Rebuild\(', 'presenter:project', 'model:snapshot', 'preview_add_one', 'rebuild_panels')) {
        Assert-True ($HandlerBlock -notmatch $Forbidden) "Custom $HandlerName hot path must exclude $Forbidden."
    }
}
$RosterStatusBlock = [regex]::Match($RosterRefreshUi, '(?ms)^function\s+UICustom:RefreshRosterStatus\(.*?^end\s*$').Value
foreach ($Required in @('presenter:refresh_status', 'presenter:refresh_affordability', 'refresh_inventory_cells')) {
    Assert-True ($RosterStatusBlock -match $Required) "Incremental roster refresh must include $Required."
}
foreach ($Forbidden in @('presenter:project', 'model:snapshot', 'preview_add_one', 'rebuild_panels', 'container:Reset', 'AddItem')) {
    Assert-True ($RosterStatusBlock -notmatch $Forbidden) "Incremental roster refresh must exclude $Forbidden."
}
$AffordabilityRefreshIndex = $RosterStatusBlock.IndexOf('self.presenter:refresh_affordability(view)')
$InventoryRefreshIndex = $RosterStatusBlock.IndexOf('refresh_inventory_cells(self.inventory_container, view.catalog_cells)')
Assert-True ($AffordabilityRefreshIndex -ge 0 -and $InventoryRefreshIndex -gt $AffordabilityRefreshIndex) `
    'Custom incremental roster refresh must update arithmetic affordability before native cells.'
$InitControlsBlock = [regex]::Match($RosterRefreshUi, '(?ms)^function\s+UICustom:InitControls\(.*?^end\s*$').Value
$InitializeFactionBlock = [regex]::Match($RosterRefreshUi, '(?ms)^function\s+initialize_faction\(.*?^end\s*$').Value
$CustomConstructorBlock = [regex]::Match($RosterRefreshUi, '(?ms)^function\s+UICustom:__init\(.*?^end\s*$').Value
Assert-True ($CustomConstructorBlock -match 'initialize_faction\(self\.model' -and
    $CustomConstructorBlock -match 'self:InitControls\(\)' -and $CustomConstructorBlock -match 'self:Rebuild\(\)') `
    'Custom constructor initialization call graph must remain structurally visible.'
foreach ($InitializationBlock in @($CustomConstructorBlock, $InitializeFactionBlock, $InitControlsBlock)) {
    Assert-True ($InitializationBlock -notmatch 'model[\.:]snapshot') `
        'Custom constructor and initialization helpers must not build a full model snapshot.'
    Assert-True ($InitializationBlock -notmatch '(?<!presenter:)project\(') `
        'Custom constructor and initialization helpers must not build the legacy full projection.'
}
Assert-True ($InitializeFactionBlock -match 'model\.status_snapshot') `
    'Custom faction initialization must use bounded status.'
Assert-True ($InitializeFactionBlock -match 'model\.catalog' -and $InitializeFactionBlock -match 'faction_ids') `
    'Custom faction initialization must use immutable catalog faction metadata.'
$InitialRebuildBlock = [regex]::Match($RosterRefreshUi, '(?ms)^function\s+UICustom:Rebuild\(.*?^end\s*$').Value
Assert-True (([regex]::Matches($InitialRebuildBlock, 'presenter:project\(')).Count -eq 1) `
    'Custom Rebuild must own exactly one authoritative full presenter projection.'
$RosterDeltaBlock = [regex]::Match($RosterRefreshUi, '(?ms)^function\s+render_roster_delta\(.*?^end\s*$').Value
Assert-True ($RosterDeltaBlock -match 'change\.previous_count') 'Incremental count rendering must be targeted by previous_count.'
Assert-True ($RosterDeltaBlock -match 'change\.rank_index') 'Incremental rank rendering must be targeted by rank_index.'
Assert-True ($RosterDeltaBlock -match 'self\.count_combo:SetText\(tostring\(view\.count\)\)') `
    'Rejected count changes must restore only the authoritative count control.'
Assert-True ($RosterDeltaBlock -match 'roster_count\(view\.count\)' -and
    $RosterDeltaBlock -match 'roster_count\(change\.previous_count\)') `
    'Incremental count rendering must validate current and previous bounds before indexing controls.'
Assert-True ($RosterDeltaBlock -match 'roster_index\(change\.rank_index\)') `
    'Incremental rank rendering must validate its fixed-control index.'
Assert-True ($RosterDeltaBlock -match 'local\s+row\s*=\s*rows\[index\]' -and
    $RosterDeltaBlock -match 'local\s+combo\s*=\s*combos\[index\]') `
    'Incremental roster rendering must defensively guard bounded native controls.'
$SharedStatusBlock = [regex]::Match($RosterRefreshUi, '(?ms)^local\s+function\s+render_roster_status\(.*?^end\s*$').Value
Assert-True ($SharedStatusBlock -match 'render_status_message\(self,\s*view\)') `
    'Incremental roster rendering must reuse the shared status and logging policy.'
$FullStatusBlock = [regex]::Match($RosterRefreshUi, '(?ms)^local\s+function\s+render_status_controls\(.*?^end\s*$').Value
Assert-True ($FullStatusBlock -match 'render_roster_status\(self,\s*view\)') `
    'Full rendering must reuse the shared roster/status policy.'
$PrepareViewStart = $RosterRefreshUi.IndexOf('local function prepare_view(self, view)')
$PrepareViewEnd = if ($PrepareViewStart -ge 0) { $RosterRefreshUi.IndexOf('local function render_status_controls', $PrepareViewStart) } else { -1 }
Assert-True ($PrepareViewStart -ge 0 -and $PrepareViewEnd -gt $PrepareViewStart) 'Custom view preparation must remain structurally testable.'
if ($PrepareViewStart -ge 0 -and $PrepareViewEnd -gt $PrepareViewStart) {
    $PrepareViewBlock = $RosterRefreshUi.Substring($PrepareViewStart, $PrepareViewEnd - $PrepareViewStart)
    Assert-True ($PrepareViewBlock -match 'view\.submission_error\s*=\s*nil') 'Custom view preparation must clear stale submission errors.'
    Assert-True ($PrepareViewBlock -match 'view\.submission_error_code\s*=\s*nil') 'Custom view preparation must clear stale submission error codes.'
}
$RosterRefreshCase = 'runtime_custom_presenter_refreshes_status_without_catalog_snapshot'
$RosterRefreshRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($RosterRefreshCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($RosterRefreshCase) + '\s*\}'
Assert-True ($RosterRefreshRuntime -match ('local\s+function\s+' + [regex]::Escape($RosterRefreshCase))) 'Custom roster refresh runtime regression is missing.'
Assert-True (([regex]::Matches($RosterRefreshRuntime, $RosterRefreshRegistration)).Count -eq 1) 'Custom roster refresh runtime regression must be registered exactly once.'
$AffordabilityCase = 'runtime_custom_presenter_refreshes_affordability_without_model_preview'
$AffordabilityRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($AffordabilityCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($AffordabilityCase) + '\s*\}'
Assert-True ($RosterRefreshRuntime -match ('local\s+function\s+' + [regex]::Escape($AffordabilityCase))) 'Custom arithmetic affordability runtime regression is missing.'
Assert-True (([regex]::Matches($RosterRefreshRuntime, $AffordabilityRegistration)).Count -eq 1) 'Custom arithmetic affordability runtime regression must be registered exactly once.'
$RosterDeltaCase = 'runtime_custom_ui_renders_only_targeted_roster_delta'
$RosterDeltaRegistration = '\{\s*name\s*=\s*"' + [regex]::Escape($RosterDeltaCase) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($RosterDeltaCase) + '\s*\}'
Assert-True ($RosterRefreshRuntime -match ('local\s+function\s+' + [regex]::Escape($RosterDeltaCase))) 'Custom targeted roster runtime regression is missing.'
Assert-True (([regex]::Matches($RosterRefreshRuntime, $RosterDeltaRegistration)).Count -eq 1) 'Custom targeted roster runtime regression must be registered exactly once.'

$CatalogCacheSource = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script') -Raw
Assert-True ($CatalogCacheSource -match 'local\s+runtime_catalog_result\s*=\s*nil') 'Runtime catalog cache must be explicit.'
Assert-True ($CatalogCacheSource -match 'ini_factory\s*==\s*nil\s+and\s+runtime_catalog_result\s*~=\s*nil') 'Only the default runtime source may read the cache.'
Assert-True ($CatalogCacheSource -match 'ini_factory\s*==\s*nil\s+and\s+result\.ok') 'Only a successful default runtime Result may populate the cache.'
$CatalogCacheCase = 'runtime_catalog_default_success_is_reused_only_for_default_source'
$CatalogCacheRegistration = '\{\s*name\s*=\s*"' + $CatalogCacheCase + '"\s*,\s*fn\s*=\s*' + $CatalogCacheCase + '\s*\}'
Assert-True (([regex]::Matches($ArenaRuntimeTestContent, $CatalogCacheRegistration)).Count -eq 1) 'Runtime catalog cache case must be registered exactly once.'

$SmokeHarnessPath = Join-Path $RepoRoot 'tests\smoke\Test-Regression.ps1'
if (Test-Path -LiteralPath $SmokeHarnessPath) {
    $SmokeHarnessContent = Get-Content -LiteralPath $SmokeHarnessPath -Raw
    $SmokeFinalPass = "Write-Host 'PASS: tool regression smoke checks passed'"
    $SmokeFinalPassIndex = $SmokeHarnessContent.LastIndexOf($SmokeFinalPass)
    $SmokeStatusReset = '$global:LASTEXITCODE = 0'
    $SmokeStatusResetIndex = $SmokeHarnessContent.LastIndexOf($SmokeStatusReset)
    Assert-True ($SmokeStatusResetIndex -ge 0 -and $SmokeFinalPassIndex -gt $SmokeStatusResetIndex) 'Successful smoke harness must restore the native exit status before its final PASS.'
    if ($SmokeStatusResetIndex -ge 0 -and $SmokeFinalPassIndex -gt $SmokeStatusResetIndex) {
        $SmokeSuccessTail = $SmokeHarnessContent.Substring($SmokeStatusResetIndex, $SmokeFinalPassIndex - $SmokeStatusResetIndex)
        Assert-True ($SmokeSuccessTail -match 'if\s*\(\s*\$global:LASTEXITCODE\s*-ne\s*0\s*\)\s*\{\s*throw') 'Smoke harness must assert the successful same-host LASTEXITCODE postcondition.'
    }
}

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

Write-Host 'PASS: static project checks passed'
