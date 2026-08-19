[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
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

Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'VERSION')) 'VERSION is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'src\gamedata')) 'src/gamedata is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot '.gitattributes')) '.gitattributes is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot '.gitignore')) '.gitignore is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'README.md')) 'README.md is missing'
Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot 'CHANGELOG.md')) 'CHANGELOG.md is missing'

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
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_runner.script'; Namespace = 'gamma_arena_test_runner'; Required = @('(?m)^function\s+run_case\s*\(', '(?m)^function\s+on_game_start\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_domain.script'; Namespace = 'gamma_arena_test_domain'; Required = @('(?m)^function\s+run\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_result.script'; Namespace = 'gamma_arena_result'; Required = @('(?m)^function\s+ok\s*\(', '(?m)^function\s+err\s*\(', '(?m)^function\s+is_ok\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_log.script'; Namespace = 'gamma_arena_log'; Required = @('(?m)^function\s+info\s*\(', '(?m)^function\s+warn\s*\(', '(?m)^function\s+error\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_rng.script'; Namespace = 'gamma_arena_rng'; Required = @('(?m)^function\s+normalize_uint32\s*\(', '(?m)^function\s+derive_seed\s*\(', '(?m)^function\s+new\s*\(', '(?m)^function\s+random_session_seed\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_state_machine.script'; Namespace = 'gamma_arena_state_machine'; Required = @('(?m)^states\s*=\s*\{', '(?m)^events\s*=\s*\{', '(?m)^function\s+transition\s*\(') }
)

$Task3ScriptContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_number.script'; Namespace = 'gamma_arena_number'; Required = @('(?m)^function\s+is_finite\s*\(', '(?m)^function\s+is_integer\s*\(', '(?m)^function\s+is_positive_integer\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_catalog.script'; Namespace = 'gamma_arena_catalog'; Required = @('(?m)^function\s+load\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_mode_skirmish.script'; Namespace = 'gamma_arena_mode_skirmish'; Required = @('(?m)^function\s+id\s*\(', '(?m)^function\s+difficulty_envelope\s*\(', '(?m)^function\s+next_fight_index\s*\(', '(?m)^function\s+validate_session\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_generator.script'; Namespace = 'gamma_arena_generator'; Required = @('(?m)^function\s+generate\s*\(', '(?m)^function\s+stable_encode\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_validator.script'; Namespace = 'gamma_arena_validator'; Required = @('(?m)^function\s+validate\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'; Namespace = 'gamma_arena_test_generator'; Required = @('(?m)^function\s+run\s*\(') }
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

$Task3DataFiles = @(
    'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx',
    'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx',
    'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx',
    'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx',
    'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx',
    'tests\fixtures\golden-fights-v1.txt',
    'schemas\fight-spec-v1.md'
)
foreach ($RelativePath in $Task3DataFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)) "Task 3 data contract is missing: $RelativePath"
}

$CatalogPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$DifficultyPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$LayoutPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
$NpcPath = Join-Path $RepoRoot 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx'
$SkipPath = Join-Path $RepoRoot 'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx'
if (Test-Path -LiteralPath $CatalogPath) {
    $CatalogContent = Get-Content -LiteralPath $CatalogPath -Raw
    Assert-True ($CatalogContent -match '(?m)^schema_version\s*=\s*1\s*$') 'Catalog must declare schema_version = 1'
    Assert-True ($CatalogContent -match '(?m)^revision\s*=\s*1\s*$') 'Catalog must declare revision = 1'
    Assert-True ($CatalogContent -match '(?ms)^\[outfit_novice\]\s+section\s*=\s*novice_outfit\s+cost\s*=\s*1\s*$') 'Novice outfit must cost 1 so every maximum-count envelope is feasible'
    foreach ($Profile in @('gamma_arena_bandit_novice', 'gamma_arena_bandit_trainee', 'gamma_arena_bandit_experienced', 'gamma_arena_bandit_veteran')) {
        Assert-True ($CatalogContent -match [regex]::Escape($Profile)) "Human profile catalog must include $Profile"
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
    Assert-True ($Task3CatalogScriptContent -match 'GA_CATALOG_MANIFEST_INVALID') 'Catalog loader must enforce the exact v1 semantic manifest'
    Assert-True ($Task3CatalogScriptContent -match 'pcall\s*\(\s*load_impl') 'Catalog load boundary must convert arbitrary fixture failures to Result errors'
    Assert-True ($Task3CatalogScriptContent -match 'v1_difficulty_manifest') 'Catalog loader must bind exact v1 difficulty semantics'
    Assert-True ($Task3CatalogScriptContent -match 'v1_layout_manifest') 'Catalog loader must bind exact ordered v1 layout semantics'
    Assert-True ($Task3CatalogScriptContent -match 'gamma_arena_number\.is_integer') 'Catalog numeric parsing must use the finite integer contract'
}
$Task3ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_validator.script'
if (Test-Path -LiteralPath $Task3ValidatorPath) {
    $Task3ValidatorContent = Get-Content -LiteralPath $Task3ValidatorPath -Raw
    foreach ($Code in @('GA_MODE_INVALID','GA_LEVEL_INVALID','GA_LAYOUT_VERSION_INVALID','GA_OPPONENT_SLOT_INVALID','GA_FIGHT_ID_INVALID','GA_FIGHTSPEC_TYPE_INVALID')) {
        Assert-True ($Task3ValidatorContent -match $Code) "Validator must return structured $Code"
    }
    Assert-True ($Task3ValidatorContent -match 'expected_fight_id') 'Validator must recompute fight_id from session_seed and fight_index'
    Assert-True ($Task3ValidatorContent -match 'GA_LOADOUT_COMBINATION_INVALID') 'Validator must reject non-v1 loadout combinations'
    Assert-True ($Task3ValidatorContent -match 'gamma_arena_number\.is_integer') 'Validator numeric fields must use the finite integer contract'
}
$Task3GeneratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_generator.script'
if (Test-Path -LiteralPath $Task3GeneratorPath) {
    $Task3GeneratorContent = Get-Content -LiteralPath $Task3GeneratorPath -Raw
    Assert-True ($Task3GeneratorContent -match 'local\s+normalized_seed\s*=\s*gamma_arena_rng\.normalize_uint32') 'Generator must normalize session_seed once'
    Assert-True ($Task3GeneratorContent -match 'session_seed\s*=\s*normalized_seed') 'FightSpec must retain normalized session_seed'
    Assert-True ($Task3GeneratorContent -match 'fight_index\s*=\s*fight_index') 'FightSpec must retain fight_index'
    Assert-True ($Task3GeneratorContent -match '"session_seed="') 'Stable encoding must include session_seed'
    Assert-True ($Task3GeneratorContent -match '"fight_index="') 'Stable encoding must include fight_index'
    Assert-True ($Task3GeneratorContent -match 'local\s+normalized_request') 'Generator must normalize the request before deriving RNG streams'
    Assert-True ($Task3GeneratorContent -match 'stream\s*\(\s*normalized_request') 'Every generated RNG stream must use the normalized request'
    Assert-True ($Task3GeneratorContent -match 'gamma_arena_number\.is_integer') 'Generator seed and index checks must use the finite integer contract'
}
if (Test-Path -LiteralPath $DifficultyPath) {
    $DifficultyContent = Get-Content -LiteralPath $DifficultyPath -Raw
    foreach ($Difficulty in @('rookie', 'stalker', 'veteran', 'master')) {
        Assert-True ($DifficultyContent -match ("(?m)^\[ga_difficulty_" + $Difficulty + "\]$")) "Difficulty catalog must include $Difficulty"
    }
}
if (Test-Path -LiteralPath $LayoutPath) {
    $LayoutContent = Get-Content -LiteralPath $LayoutPath -Raw
    Assert-True ($LayoutContent -match '(?m)^level\s*=\s*l05_bar\s*$') 'Layout must target l05_bar'
    Assert-True ($LayoutContent -match 'bar_arena_walk_3_1,bar_arena_walk_3_2,bar_arena_walk_6_1,bar_arena_walk_6_3,bar_arena_walk_6_6,bar_arena_monstr_walk') 'Layout must retain the six unique opponent paths'
}
if (Test-Path -LiteralPath $NpcPath) {
    $NpcContent = Get-Content -LiteralPath $NpcPath -Raw
    Assert-True ($NpcContent -match '(?m)^\[gamma_arena_bandit_novice\]:sim_default_bandit_0$') 'NPC novice profile must inherit sim_default_bandit_0'
    Assert-True ($NpcContent -match '(?m)^\[gamma_arena_bandit_veteran\]:sim_default_bandit_3$') 'NPC veteran profile must inherit sim_default_bandit_3'
}
if (Test-Path -LiteralPath $SkipPath) {
    $SkipContent = Get-Content -LiteralPath $SkipPath -Raw
    Assert-True ($SkipContent -match '(?m)^!\[skip_npcs\]\s*$') 'Loadout patch must use ![skip_npcs]'
    Assert-True (([regex]::Matches($SkipContent, '(?m)^gamma_arena_bandit_[a-z]+\s*=\s*bandit\s*$')).Count -eq 4) 'Loadout patch must add exactly four Arena humans to skip_npcs'
}
$GoldenPath = Join-Path $RepoRoot 'tests\fixtures\golden-fights-v1.txt'
if (Test-Path -LiteralPath $GoldenPath) {
    $GoldenContent = Get-Content -LiteralPath $GoldenPath -Raw
    Assert-True (([regex]::Matches($GoldenContent, '(?m)^seed=\d+,difficulty=(rookie|stalker|veteran|master),fight=\d+,stable_encode=schema_version=1\|.+\|diagnostic=FightSpecV1 .+$')).Count -eq 4) 'Golden fixture must contain four complete v1 stable encodings'
}

$Task2RunnerPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runner.script'
$Task2LogPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_log.script'
$Task2RngPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_rng.script'
if (Test-Path -LiteralPath $Task2RunnerPath) {
    $Task2RunnerContent = Get-Content -LiteralPath $Task2RunnerPath -Raw
    Assert-True ($Task2RunnerContent -match '(?s)pcall\s*\(\s*function\s*\(\s*\)\s*return\s+gamma_arena_test_domain\.run\s*\(\s*run_case\s*\)\s*end\s*\)') 'Dev test runner must resolve and execute the domain suite inside pcall'
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

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

Write-Host 'PASS: static project checks passed'
