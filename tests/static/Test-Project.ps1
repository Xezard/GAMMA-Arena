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

$AllLuaScripts = @(Get-ChildItem -LiteralPath $RepoRoot -File -Recurse -Filter '*.script' | Where-Object {
    $_.FullName -notmatch '[\\/](dist|build)[\\/]'
})
foreach ($Script in $AllLuaScripts) {
    Assert-True (-not (Test-TextPattern $Script.FullName '(?m)\b[A-Za-z_][A-Za-z0-9_]*\.[0-9][A-Za-z0-9_.]*\s*=')) "Invalid bare Lua table key containing a dot: $(Get-RelativeRepoPath $Script.FullName)"
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
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_mode_skirmish.script'; Namespace = 'gamma_arena_mode_skirmish'; Required = @('(?m)^function\s+id\s*\(', '(?m)^function\s+difficulty_envelope\s*\(', '(?m)^function\s+next_fight_index\s*\(', '(?m)^function\s+validate_session\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_generator.script'; Namespace = 'gamma_arena_generator'; Required = @('(?m)^function\s+generate\s*\(', '(?m)^function\s+stable_encode\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_validator.script'; Namespace = 'gamma_arena_validator'; Required = @('(?m)^function\s+validate\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_layout_adapter.script'; Namespace = 'gamma_arena_layout_adapter'; Required = @('(?m)^function\s+new\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script'; Namespace = 'gamma_arena_test_generator'; Required = @('(?m)^function\s+run\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_catalog_discovery.script'; Namespace = 'gamma_arena_test_catalog_discovery'; Required = @('(?m)^function\s+run\s*\(') },
    [PSCustomObject]@{ Path = 'dev\gamedata\scripts\gamma_arena_test_layout_adapter.script'; Namespace = 'gamma_arena_test_layout_adapter'; Required = @('(?m)^function\s+run\s*\(') }
)

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
    'schemas\session-v1.md',
    'docs\compatibility.md'
)
foreach ($RelativePath in $Task4DataFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)) "Task 4 data contract is missing: $RelativePath"
}

$MigrationPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_migrations.script'
if (Test-Path -LiteralPath $MigrationPath) {
    $MigrationContent = Get-Content -LiteralPath $MigrationPath -Raw
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
    foreach ($Key in @('launch_pending','launch_token','launch_mode_id','launch_difficulty_id','launch_seed_mode','launch_session_seed','launch_stage','launch_deferred_level','launch_target_level','resume_pending','resume_session_id','resume_session_nonce','resume_next_fight_index','resume_checkpoint_name','resume_schema_version')) {
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
    Assert-True ($DxmlContent -match 'getElementPosition') 'DXML handler must derive the insertion point from New Game'
    Assert-True ($DxmlContent -match 'new_game_position\s*\+\s*1') 'Arena must be inserted immediately after New Game'
    Assert-True ($DxmlContent -notmatch 'menu\[1\]\s*,\s*#menu\[1\]\.kids') 'Arena insertion must not use an end-relative menu position'
    foreach ($Code in @('GA_DXML_POSITION_API_UNAVAILABLE','GA_DXML_MENU_MISSING','GA_DXML_NEW_GAME_MISSING','GA_DXML_NEW_GAME_PARENT_MISMATCH','GA_DXML_NEW_GAME_POSITION_INVALID')) {
        Assert-True ($DxmlContent -match [regex]::Escape($Code)) "DXML placement must fail closed with $Code"
    }
    Assert-True (([regex]::Matches($DxmlContent, '<btn name="btn_gamma_arena" caption="st_gamma_arena_main_menu"\s*/>')).Count -eq 1) 'DXML module must contain exactly one Arena button insertion'
    Assert-True ($DxmlContent -match 'insertFromXMLString') 'DXML handler must insert through insertFromXMLString'
    Assert-True ($DxmlContent -match 'pcall\s*\(\s*(gamma_arena_log\.error|logger)\s*,\s*result\.error\.code\s*,\s*result\.error\.message\s*,\s*result\.error\.context') 'DXML callback must internally log structured failures because callback returns are ignored'
}

$Task4DevTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_migrations.script'
if (Test-Path -LiteralPath $Task4DevTestPath) {
    $Task4DevTestContent = Get-Content -LiteralPath $Task4DevTestPath -Raw
    Assert-True ($Task4DevTestContent -match 'character_creation_bridge_accepts_engine_nil_for_present_empty_values') 'Task 4 Dev tests must cover engine nil for present empty character-creation values'
    foreach ($Marker in @('stale_launch_is_recovered_by_new_store','launch_survives_vm_reload_with_matching_bridge_lease','launch_handoff_rejects_mismatched_or_expired_lease','serialized_launch_requires_fake_start_phase_proof','same_store_corrupt_launch_is_replaced','resume_rejects_tampered_expected_session','mutation_failure_matrix_is_crash_safe','recovery_failure_quarantines_transaction','read_and_false_return_faults_are_safe','stale_cleanup_and_conflict_faults_are_safe','matching_resume_cleanup_is_session_scoped','prepared_resume_consume_rejects_persisted_drift','dxml_accepts_canonical_callback_path','dxml_registers_first_main_menu_click','dxml_registration_failures_are_structured','dxml_places_arena_after_new_game','dxml_placement_failures_are_structured','character_creation_bridge_restores_exactly_from_fresh_store','ordinary_character_creation_without_lease_is_untouched','character_creation_bridge_restores_on_every_launch_terminal_route','character_creation_bridge_faults_fail_closed','start_game_failures_restore_bridge_immediately','arm_fault','arm_read_fault','arm_recovery_fault','persisted')) {
        Assert-True ($Task4DevTestContent -match $Marker) "Task 4 Dev tests must cover $Marker"
    }
}

$MainMenuPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_main_menu.script'
if (Test-Path -LiteralPath $MainMenuPath) {
    $MainMenuContent = Get-Content -LiteralPath $MainMenuPath -Raw
    Assert-True ($MainMenuContent -match '(?m)^function\s+on_main_menu_init\s*\(') 'Main-menu adapter must export its main_menu_on_init bridge'
    Assert-True ($MainMenuContent -notmatch '(?m)^function\s+on_game_start\s*\(') 'Main-menu adapter must not register after the first cold-start init'
    Assert-True ($MainMenuContent -notmatch 'RegisterScriptCallback') 'Main-menu adapter registration must be owned by the early DXML bootstrap'
    Assert-True ($MainMenuContent -match 'type\s*\(\s*menu\.AddCallback\s*\)\s*==\s*"function"') 'Main-menu adapter must feature-probe AddCallback'
    Assert-True ($MainMenuContent -match 'AddCallback\s*\(\s*"btn_gamma_arena"\s*,\s*ui_events\.BUTTON_CLICKED') 'Main-menu adapter must bind only btn_gamma_arena'
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
    Assert-True (([regex]::Matches($UiContent, 'issue_launch\s*\(')).Count -ge 2) 'Start UI stale recovery must perform a fresh launch issuance attempt'
    Assert-True ($UiContent -match 'function\s+invoke_fatal_main_menu') 'Fatal UI must expose a total callback-result propagation seam'
    Assert-True ($UiContent -match 'return\s+invoke_fatal_main_menu') 'Fatal UI action must propagate the disconnect Result to its caller'
    Assert-True ($UiContent -match 'function\s+handoff_start_game') 'Start UI must expose a total engine-handoff seam for behavioral fault injection'
    Assert-True ($UiContent -match 'detail\s*==\s*false') 'Start UI must treat explicit false StartGame as a structured failure'
    Assert-True ($UiContent -match 'handoff_start_game\s*\(\s*self\.owner\s*,\s*axr_main\.config\s*\)') 'OnStart must route engine handoff through immediate common cleanup on failure'
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
        foreach ($Id in @('st_gamma_arena_title','st_gamma_arena_difficulty_rookie','st_gamma_arena_difficulty_stalker','st_gamma_arena_difficulty_veteran','st_gamma_arena_difficulty_master','st_gamma_arena_random_seed','st_gamma_arena_start','st_gamma_arena_back','st_gamma_arena_fatal_title','st_gamma_arena_fatal_error_line','st_gamma_arena_fatal_main_menu','st_gamma_arena_seed_invalid','st_gamma_arena_manual_save_disabled','st_gamma_arena_result_victory','st_gamma_arena_result_defeat','st_gamma_arena_result_main_menu','st_gamma_arena_result_next')) {
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
    foreach ($Callback in @('on_game_load','actor_on_first_update','actor_on_update','actor_on_before_death','npc_on_death_callback','save_state','load_state','on_before_save_input','on_before_load_input','actor_on_net_destroy','on_before_level_changing')) {
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
    foreach ($Marker in @('l05_bar','AI_STL_S','bandit','point','level_vertex_id','game_vertex_id','4294967295','GA_PREFLIGHT_PATROL_MISSING','GA_PREFLIGHT_PATROL_INVALID','GA_PREFLIGHT_SECTION_MISSING','GA_NPC_CLASS_API_MISSING','GA_NPC_CLASS_MISSING','GA_NPC_CLASS_READ_FAILED','GA_NPC_CLASS_INVALID','GA_NPC_COMMUNITY_API_MISSING','GA_NPC_COMMUNITY_MISSING','GA_NPC_COMMUNITY_READ_FAILED','GA_NPC_COMMUNITY_INVALID')) {
        Assert-True ($Task5CompatContent -match [regex]::Escape($Marker)) "Preflight must enforce $Marker"
    }
    Assert-True ($Task5CompatContent -match 'engine_callable_present') 'Preflight must accept callable engine objects whose Lua type is not function'
    Assert-True ($Task5CompatContent -notmatch 'type\(p\.ini_file\)\s*==\s*["'']function["'']') 'Preflight must not reject the callable ini_file engine object by Lua type'
    Assert-True ($Task5CompatContent -notmatch 'type\(p\.patrol\)\s*==\s*["'']function["'']') 'Preflight must not reject the callable patrol engine object by Lua type'
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
}

$Task5StorePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script'
if (Test-Path -LiteralPath $Task5StorePath) {
    $Task5StoreContent = Get-Content -LiteralPath $Task5StorePath -Raw
    Assert-True ($Task5StoreContent -match 'GA_SESSION_UNKNOWN_FIELD') 'ArenaSession validator must reject unknown/future fields'
    Assert-True ($Task5StoreContent -match 'function Store:inspect_intents') 'Session store must expose non-mutating intent inspection'
    Assert-True ($Task5StoreContent -match 'function Store:prepare_resume') 'Session store must validate a resume route before checkpoint re-hide'
    Assert-True ($Task5StoreContent -match 'function Store:clear_resume_if_matches') 'Checkpoint cleanup must clear only a ResumeIntent bound to its ArenaSession'
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
    foreach ($Marker in @('runtime_preflight_aggregates_in_stable_order','runtime_preflight_requires_task6_actor_checkpoint_ports','runtime_preflight_requires_community_for_every_custom_profile','runtime_preflight_requires_human_class_for_every_custom_profile','runtime_preflight_rejects_missing_profile_value_apis','runtime_preflight_normalizes_effective_bandit_community','runtime_wrong_level_skips_patrol_resolution','runtime_launch_consumes_before_preflight_once','runtime_activation_requires_game_load_boundary','runtime_launch_defers_on_fake_start_then_activates_on_rostok','runtime_ordinary_no_intent_activation_latches_once','runtime_first_activation_failure_routes_fatal','runtime_activation_reconciles_before_intent_inspection_once','runtime_activation_version_changes_clear_resume_before_checkpoint_routing','runtime_activation_reconciliation_failures_are_fatal_before_inspection','runtime_invalid_or_expired_launch_never_reaches_preflight','runtime_ordinary_loaded_save_rejects_stray_launch','runtime_ordinary_loaded_save_rejects_stray_resume','runtime_new_game_does_not_reuse_prior_load_state_latch','runtime_game_load_boundary_drops_prior_runtime_generation','runtime_config_quarantine_propagates_to_fatal','runtime_save_payload_is_plain_deep_copy','runtime_manual_save_and_load_flags_are_blocked','runtime_callback_boundary_routes_exceptions_once','runtime_callback_boundary_routes_false_results_once','runtime_inactive_callback_results_remain_benign','runtime_active_save_failure_enters_fatal_once','runtime_fatal_main_menu_retries_throw_then_becomes_idempotent','runtime_fatal_main_menu_retries_explicit_false','runtime_fatal_ui_helper_propagates_callback_results','runtime_bootstrap_registration_rolls_back_every_position','runtime_bootstrap_registration_poison_blocks_retry','runtime_bootstrap_requires_unregister_before_composition','runtime_unexpected_net_destroy_clears_external_route')) {
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
    Assert-True ($Task9UiContent -match 'OnKeyboard[\s\S]{0,500}DIK_RETURN[\s\S]{0,240}DIK_SPACE[\s\S]{0,240}self:OnNext\(\)[\s\S]{0,120}return\s+true') 'Task 9 result keyboard fallback must route Enter/Space to the next-fight action'
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
if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    foreach ($Marker in @('death_latched','pending_result','ret_value','hold_after_logical_death','release_logical_death_hold','show_defeat','defeat_next_action','NEXT_AFTER_DEFEAT','drive_continuation')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Task 9 orchestrator must cover $Marker"
    }
    Assert-True ($Task5OrchestratorContent -match 'show_countdown["'']\s*,\s*\{[\s\S]{0,500}on_main_menu') 'Task 9 countdown model must route the common Arena main-menu cleanup'
    $Task9VictoryBlock = [regex]::Match($Task5OrchestratorContent, 'function\s+Orchestrator:show_victory\(\)[\s\S]*?[\r\n]+end').Value
    $Task9DefeatBlock = [regex]::Match($Task5OrchestratorContent, 'function\s+Orchestrator:show_defeat\(\)[\s\S]*?[\r\n]+end').Value
    Assert-True ($Task9VictoryBlock -notmatch 'acquire_input') 'Victory result modal must not globally disable mouse input'
    Assert-True ($Task9DefeatBlock -match 'release_input') 'Defeat result modal must release logical-death global input before showing UI'
    Assert-True ($Task5OrchestratorContent -match 'if\s+state\.resume_pending\s+then[\s\S]{0,300}GA_RESUME_UNSUPPORTED') 'Legacy ResumeIntent must fail safely without checkpoint recovery'
    Assert-True ($Task5OrchestratorContent -notmatch 'checkpoint_restore_failure|normalize_resume_preparation') 'Checkpoint recovery normalizers must be absent from dedicated Arena runtime'
}
$Task9ActorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_actor_adapter.script'
if (Test-Path -LiteralPath $Task9ActorPath) {
    $Task9ActorContent = Get-Content -LiteralPath $Task9ActorPath -Raw
    Assert-True ($Task9ActorContent -match [regex]::Escape('cleanup_loadout_for_restore')) 'Task 9 actor adapter must expose owned-loadout-only cleanup before restore'
}
if (Test-Path -LiteralPath $Task5DevTestPath) {
    foreach ($Marker in @('runtime_preflight_requires_task9_death_hold_port','runtime_task9_ordinary_death_is_inert','runtime_task9_active_death_latches_and_defers_defeat','runtime_task9_death_outside_active_is_not_a_defeat','runtime_task9_single_result_contract_maps_both_kinds','runtime_task9_countdown_escape_model_routes_main_menu_cleanup','runtime_task9_resume_failures_normalize_to_restore_failed','runtime_task9_defeat_retry_reuses_same_spec_without_checkpoint','runtime_task9_defeat_and_victory_share_main_menu_cleanup','runtime_task9_restore_failure_enters_error_with_safe_menu_only','runtime_fight_index_max_minus_one_advances_once','runtime_fight_index_exhaustion_precedes_mutation_and_routes_fatal','runtime_actor_loadout_consumed_absent_id_retires_without_release','runtime_actor_loadout_pre_release_reused_foreign_id_is_never_released','runtime_actor_loadout_post_submit_reuse_is_never_released_twice','runtime_actor_loadout_malformed_ownership_proof_fails_closed','runtime_actor_loadout_exact_owned_match_releases_once','runtime_actor_loadout_apply_failures_never_drop_valid_created_ids','runtime_actor_loadout_failed_tag_write_never_manufactures_ownership','runtime_task9_resume_pending_invalid_loaded_session_normalizes','runtime_task9_restoring_state_read_failure_normalizes','runtime_task9_resume_completion_transition_failure_normalizes')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 9 Dev tests must cover $Marker"
    }
}
if (Test-Path -LiteralPath $Task5CompatPath) {
    Assert-True ($Task5CompatContent -match [regex]::Escape('db.actor.set_invulnerable/invulnerable')) 'Task 9 preflight must require a proven logical-death hold API'
}
if (Test-Path -LiteralPath $Task5BootstrapPath) {
    Assert-True ($Task5BootstrapContent -match 'actor\.set_invulnerable') 'Task 9 bootstrap must bind the proven actor logical-death hold API'
    Assert-True ($Task5BootstrapContent -match 'gamma_arena_ui_result\.new\s*\(') 'Task 9 bootstrap must replace the Task 8 UI placeholder with the real adapter'
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
    foreach ($Marker in @('normalize_for_arena','verify_inventory_empty','apply_loadout','reset_for_rematch','hold_after_logical_death','release_logical_death_hold','begin_update','iterate_inventory','"parent"','release_item_id','set_health_ex','set_actor_condition','power','radiation','bleeding','psy_health','give_money','disable_effects_timer','set_actor_position','set_actor_direction','input_owned','GA_ACTOR_INACTIVE')) {
        Assert-True ($Task6ActorContent -match [regex]::Escape($Marker)) "Actor adapter must cover $Marker"
    }
    Assert-True ($Task6ActorContent -notmatch 'function\s+ActorAdapter:enforce_boundary') 'Closed Rostok Arena must not run a per-update actor boundary teleport guard'
    Assert-True ($Task6ActorContent -match 'function\s+ActorAdapter:reset_for_rematch') 'Actor adapter must expose one shared in-memory rematch reset'
    Assert-True ($Task6ActorContent -notmatch 'call_actor\s*\(\s*item\s*,\s*["'']parent_id["'']') 'Actor adapter must use the real client game_object parent():id() API, never nonexistent parent_id()'
    Assert-True ($Task6ActorContent -match '"bleeding"\s*,\s*1') 'GAMMA actor normalization must use the observed cured bleeding sentinel 1'
    Assert-True ($Task6ActorContent.Contains('mod_body_health_reset')) 'Actor adapter must reset GAMMA Body Health System state between rounds'
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
foreach ($Marker in @('zzz_player_injuries', 'BHS_PARTS', 'bhs.health', 'bhs.maxhp', 'bhs.timedhp', 'utils_obj.save_var', 'utils_obj.load_var', 'mod_body_health_reset')) {
    Assert-True ($Task6BootstrapContent.Contains($Marker)) "Bootstrap GAMMA Body Health integration is missing marker: $Marker"
}

$CheckpointFreeStatePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_state_machine.script'
if (Test-Path -LiteralPath $CheckpointFreeStatePath) {
    $CheckpointFreeStateContent = Get-Content -LiteralPath $CheckpointFreeStatePath -Raw
    Assert-True ($CheckpointFreeStateContent -match '\[event_values\.PREFLIGHT_SUCCEEDED\]\s*=\s*state_values\.PREPARING') 'Dedicated Arena preflight must advance directly to PREPARING'
    Assert-True ($CheckpointFreeStateContent -notmatch 'state_values\.(CHECKPOINTING|RECOVERING)') 'Dedicated Arena state graph must not contain checkpoint or save-recovery states'
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
    foreach ($Marker in @('time_global','level.disable_input','level.enable_input','db.actor.iterate_inventory','db.actor.power','db.actor.radiation','db.actor.bleeding','db.actor.psy_health','db.actor.set_actor_position')) {
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
    Assert-True ($Task5OrchestratorContent -match 'pending_continuation_kind\s*=\s*"defeat_retry"') 'Defeat retry must select the in-memory continuation path'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:drive_continuation') 'Victory and defeat must share one bounded continuation transaction'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:drive_continuation[\s\S]{0,5000}pending_continuation_kind[\s\S]{0,5000}begin_apply[\s\S]{0,1500}fight_spec') 'Defeat retry must retain and reapply the immutable FightSpec'
    Assert-True ($Task5OrchestratorContent -notmatch 'function\s+Orchestrator:defeat_next_action[\s\S]{0,1800}resolve_next_fight_index') 'Defeat retry must not advance fight_index'
    Assert-True ($Task5OrchestratorContent -match 'function\s+Orchestrator:observe_entity_activation[\s\S]{0,900}release_logical_death_hold[\s\S]{0,600}release_input') 'Fresh ACTIVE must release the logical-death hold before returning player input'
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
    foreach ($Marker in @('begin_apply','update','on_npc_death','living_opponent_count','cleanup','registry_snapshot','gamma_arena_owner','se_load_var','get_children','parent_id','safe_release_manager','set_relation','game_object.enemy','game_object.friend','-5000','AI_STL_S','bandit','persist_death_dropped','GA_ENTITY_DEATH_DROPPED_VERIFY_FAILED','hold_offline','request_online','online_requested','held_offline','staged_friendly','set_actor_hold','GA_ENTITY_ACTIVATION_HOLD_FAILED','GA_ENTITY_ONLINE_REQUEST_FAILED','GA_ENTITY_ONLINE_TIMEOUT','GA_ENTITY_RELEASE_TIMEOUT','GA_ENTITY_PARENT_RELEASE_BLOCKED','GA_ENTITY_CHILD_PARENT_UNPROVEN','register_and_tag_created_item','profile_runtime','ammo_box_size','ammo_rounds')) {
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
    Assert-True ($Task7EntityContent -match 'expected_created_quantity') 'Opponent loadout must derive exact ammo allocation when server quantity is unavailable'
    Assert-True ($Task7EntityContent -match 'community\s*=\s*participant\.community') 'Entity adapter participant copies must preserve dynamic FightSpec community'
    Assert-True ($Task7EntityContent -notmatch 'ensure_weapon_equipped|GA_ENTITY_EQUIP_TIMEOUT') 'NPC activation must not wait for a weapon to become active before hostility starts combat AI'
}

$Task7ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_validator.script'
if (Test-Path -LiteralPath $Task7ValidatorPath) {
    $Task7ValidatorContent = Get-Content -LiteralPath $Task7ValidatorPath -Raw
    foreach ($Marker in @('effective_profile','validate_runtime','AI_STL_S','bandit','GA_ENEMY_EFFECTIVE_CLASS_INVALID','GA_ENEMY_EFFECTIVE_COMMUNITY_INVALID','GA_ENEMY_EFFECTIVE_PROFILE_API_MISSING')) {
        Assert-True ($Task7ValidatorContent -match [regex]::Escape($Marker)) "Task 7 validator must cover $Marker"
    }
}

$Task7FixturePath = Join-Path $RepoRoot 'tests\fixtures\effective-arena-npcs-v1.ini'
Assert-True (Test-Path -LiteralPath $Task7FixturePath) 'Task 7 effective NPC fixture is missing'
if (Test-Path -LiteralPath $Task7FixturePath) {
    $Task7FixtureContent = Get-Content -LiteralPath $Task7FixturePath -Raw
    Assert-True (([regex]::Matches($Task7FixtureContent, '(?m)^section\s*=\s*gamma_arena_bandit_(novice|trainee|experienced|veteran)\s*$')).Count -eq 4) 'Effective NPC fixture must contain exactly four Arena sections'
    Assert-True (([regex]::Matches($Task7FixtureContent, '(?m)^class\s*=\s*AI_STL_S\s*$')).Count -eq 4) 'Every effective Arena NPC must resolve to AI_STL_S'
    Assert-True (([regex]::Matches($Task7FixtureContent, '(?m)^community\s*=\s*bandit\s*$')).Count -eq 4) 'Every effective Arena NPC must resolve to bandit'
    Assert-True ($Task7FixtureContent -notmatch '(?m)^death_dropped\s*=') 'Effective-profile fixture must not pretend the runtime death-manager save-var is an LTX property'
}

$Task7NpcPath = Join-Path $RepoRoot 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx'
if (Test-Path -LiteralPath $Task7NpcPath) {
    $Task7NpcContent = Get-Content -LiteralPath $Task7NpcPath -Raw
    Assert-True ($Task7NpcContent -notmatch '(?m)^death_dropped\s*=') 'Arena NPC LTX must not treat death_dropped as an inert section property'
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
    Assert-True ($Task5BootstrapContent -match 'local\s+function\s+entity_ammo_quantity[\s\S]{0,900}return\s+nil\s*[\r\n]+end') 'NPC production quantity port must expose unavailable server ammo quantity as nil for exact box-size derivation'
    Assert-True ($Task5BootstrapContent -notmatch 'Ammo server entity does not expose its exact round count') 'NPC production quantity port must not turn unavailable server binding metadata into a fatal Result'
    Assert-True ($Task5BootstrapContent -notmatch 'ensure_entity_weapon_equipped|GA_ENTITY_EQUIP_TIMEOUT') 'Bootstrap must leave NPC weapon selection to combat AI after validated inventory ownership'
    $Task11HostilityBlock = [regex]::Match($Task5BootstrapContent, 'function\s+apply_actor_hostility[\s\S]*?local\s+function\s+apply_actor_activation_hold').Value
    Assert-True ($Task11HostilityBlock -match 'set_relation[\s\S]*force_set_goodwill') 'Hostile activation must apply relation then goodwill'
    Assert-True ($Task11HostilityBlock -notmatch 'make_object_visible_somewhen|set_enemy') 'Hostile activation must not seed omniscient memory or force a current target'
    Assert-True ($Task5BootstrapContent -match 'reserve_magazines\s*=\s*3') 'Production actor loadout must provide at least three full reserve magazines'
    Assert-True ($Task5BootstrapContent -match 'function\s+engine_inventory_slot\(ltx_slot\)[\s\S]{0,700}ltx_slot\s*\+\s*1') 'Actor loadout must translate zero-based LTX slots to one-based Lua inventory API slots'
    foreach ($Marker in @('WAIT_SLOT_VERIFY','WAIT_MAGAZINE_VERIFY','WAIT_ACTIVE_VERIFY')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Actor equipment must retain cross-frame phase $Marker"
    }
    foreach ($Marker in @('WAIT_ACTOR_LOADOUT','move_to_slot','item_in_slot','set_ammo_elapsed','get_ammo_in_magazine','ammo_mag_size','update_loadout','GA_ACTOR_LOADOUT_EQUIP_TIMEOUT')) {
        Assert-True (($Task5BootstrapContent + $Task7EntityContent + $Task6ActorContent) -match [regex]::Escape($Marker)) "Equipped actor loadout must cover $Marker"
    }
    foreach ($Marker in @('runtime_actor_loadout_derives_unreadable_server_ammo_quantity','runtime_entity_derives_unreadable_server_ammo_quantity','runtime_actor_loadout_translates_ltx_slots_to_lua_slots','runtime_actor_loadout_progress_survives_clock_stalls','runtime_actor_loadout_no_progress_timeout_has_context')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Runtime ammo allocation regression must cover $Marker"
    }
    foreach ($Marker in @('last_progress_at','elapsed_since_progress_ms','total_elapsed_ms')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Actor equipment inactivity timeout must expose $Marker"
    }
    Assert-True ($Task5DevTestContent -match [regex]::Escape('runtime_result_modal_releases_global_input')) 'Runtime result modal must prove global input ownership is released'
}

if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    foreach ($Marker in @('entities','on_npc_death','living_opponent_count','GA_ENTITY_COUNT_UNAVAILABLE','GA_ENTITY_COUNT_STATE_INVALID')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Task 7 orchestration integration must cover $Marker"
    }
    Assert-True ($Task5OrchestratorContent -match 'if\s+not\s+self:is_active\(\)\s+and\s+self\.cleanup_required\s+then\s+return\s+self:drive_runtime\(\)\s+end') 'Inactive cleanup polling must not bypass launch/resume activation while awaiting_activation is set'
    Assert-True ($Task5OrchestratorContent -match 'if\s+self\.cleanup_required\s+then[\s\S]{0,500}self:cleanup_ready_for_disconnect\(\)') 'A later loaded Arena must consume exact cleanup readiness before launch/resume activation'
}

if (Test-Path -LiteralPath $Task5DevTestPath) {
    foreach ($Marker in @('runtime_preflight_requires_task7_entity_ports_and_ammo_metadata','runtime_entity_actor_loadout_precedes_spawn','runtime_entity_npcs_are_offline_until_atomic_activation','runtime_entity_online_wait_is_bounded_and_wrap_safe','runtime_entity_active_defers_input_release_to_task8','runtime_bootstrap_actor_loadout_port_is_bound_and_exact','runtime_actor_loadout_rollback_blocks_disconnect_until_absent','runtime_actor_loadout_malformed_existence_blocks_teardown_disconnect','runtime_bootstrap_actor_existence_lookup_fails_closed','runtime_bootstrap_hostility_port_is_feature_probed','runtime_entity_ammo_box_size_failure_precedes_actor_mutation','runtime_entity_partial_failures_rollback_in_reverse','runtime_entity_purges_only_snapshot_children_still_parented','runtime_entity_supports_real_get_children_iterator','runtime_entity_multi_return_ammo_is_exact','runtime_entity_death_dropped_is_persisted_and_round_tripped','runtime_entity_multi_return_late_failure_is_fully_registered','runtime_entity_multi_return_invalid_or_duplicate_id_rolls_back_every_owned_creation','runtime_entity_registry_is_plain_ids_only','runtime_entity_cleanup_requires_registry_and_tag','runtime_entity_forged_tag_is_ignored','runtime_entity_tag_loss_fails_safe','runtime_entity_parent_release_blocks_unproven_children','runtime_entity_parent_release_blocks_unreadable_child_parent','runtime_entity_cleanup_is_idempotent','runtime_entity_lifecycle_cleanup_takes_over_mid_rollback','runtime_entity_existence_result_must_be_boolean','runtime_entity_duplicate_death_is_idempotent','runtime_entity_unregistered_death_is_ignored','runtime_entity_object_death_signature_is_normalized','runtime_entity_numeric_death_requires_test_injection','runtime_registered_death_owner_tag_failures_route_through_real_callback_router','runtime_registered_death_mismatching_owner_tag_is_benign','runtime_entity_release_is_async_and_never_direct','runtime_entity_release_timeout_is_wrap_safe','runtime_entity_max_cardinality_cleanup_fits_default_budget','runtime_entity_relations_friend_first_then_actor_hostile','runtime_entity_activation_does_not_wait_for_precombat_active_item','runtime_entity_callbacks_fail_closed','runtime_validator_rejects_effective_nonhuman_profile','runtime_entity_runtime_profile_check_precedes_actor_mutation','runtime_orchestrator_living_count_fails_closed','runtime_entity_does_not_spawn_before_begin_apply')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 7 Dev tests must cover $Marker"
    }
}

$Task3DataFiles = @(
    'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx',
    'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx',
    'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx',
    'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx',
    'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx',
    'tests\fixtures\golden-fights-v3.txt',
    'schemas\fight-spec-v3.md'
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
    Assert-True ($CatalogContent -match '(?m)^schema_version\s*=\s*3\s*$') 'Catalog must declare schema_version = 3'
    Assert-True ($CatalogContent -match '(?m)^revision\s*=\s*3\s*$') 'Catalog must declare revision = 3'
    Assert-True ($CatalogContent -match '(?m)^generator_version\s*=\s*4\s*$') 'Catalog must declare generator_version = 4'
    Assert-True (([regex]::Matches($CatalogContent, '(?m)^section\s*=\s*wpn_knife[2-9]?\s*$')).Count -eq 9) 'Knife catalog must contain exactly the nine installed GAMMA knife sections'
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
    Assert-True ($Task3CatalogScriptContent -match 'GA_CATALOG_MANIFEST_INVALID') 'Catalog loader must enforce the exact v3 semantic manifest'
    Assert-True ($Task3CatalogScriptContent -match 'pcall\s*\(\s*load_impl') 'Catalog load boundary must convert arbitrary fixture failures to Result errors'
    Assert-True ($Task3CatalogScriptContent -match 'difficulty_manifest_v2') 'Catalog loader must bind exact v2 difficulty semantics'
    Assert-True ($Task3CatalogScriptContent -match 'layout_manifest_v2') 'Catalog loader must bind exact ordered v2 layout semantics'
    Assert-True ($Task3CatalogScriptContent -match 'gamma_arena_number\.is_integer') 'Catalog numeric parsing must use the finite integer contract'
}
$Task3ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_validator.script'
if (Test-Path -LiteralPath $Task3ValidatorPath) {
    $Task3ValidatorContent = Get-Content -LiteralPath $Task3ValidatorPath -Raw
    foreach ($Code in @('GA_MODE_INVALID','GA_LEVEL_INVALID','GA_LAYOUT_VERSION_INVALID','GA_OPPONENT_SLOT_INVALID','GA_FIGHT_ID_INVALID','GA_FIGHTSPEC_TYPE_INVALID')) {
        Assert-True ($Task3ValidatorContent -match $Code) "Validator must return structured $Code"
    }
    Assert-True ($Task3ValidatorContent -match 'expected_fight_id') 'Validator must recompute fight_id from session_seed and fight_index'
    Assert-True ($Task3ValidatorContent -match 'GA_LOADOUT_COMBINATION_INVALID') 'Validator must reject non-v2 loadout combinations'
    Assert-True ($Task3ValidatorContent -match 'GA_LOADOUT_KNIFE_INVALID') 'Validator must reject non-cataloged knives'
    Assert-True ($Task3ValidatorContent -match 'GA_ENEMY_SLOT_BUDGET_INVALID') 'Validator must enforce deterministic per-slot enemy budgets'
    foreach ($Code in @('GA_SPAWN_SLOT_INVALID','GA_SPAWN_SLOT_DUPLICATE','GA_TACTICAL_ROUTE_INVALID','GA_ENEMY_ROLE_INVALID','GA_ENEMY_PRIMARY_SHARE_INVALID','GA_ENEMY_SNIPER_LIMIT_INVALID')) {
        Assert-True ($Task3ValidatorContent -match $Code) "FightSpec v3 validator must return structured $Code"
    }
    Assert-True ($Task3ValidatorContent -match 'math\.floor\s*\(\s*difficulty\.enemy_total_budget\s*/\s*opponent_count\s*\)') 'Validator must recompute the generator slot-budget base'
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
    Assert-True ($Task3GeneratorContent -match '"actor_knife"') 'Player knife must use an independent tagged RNG stream'
    Assert-True ($Task3GeneratorContent -match 'schema_version\s*=\s*3') 'Generator must emit FightSpecV3'
    foreach ($Marker in @('pick_affordable_band','primary_share_percent','spawn_slot_id','tactical_route','role_weapon_pool','resolved_layout')) {
        Assert-True ($Task3GeneratorContent -match $Marker) "FightSpec v3 generator must contain $Marker"
    }
    Assert-True ($Task3GeneratorContent -match 'global_role_pool') 'Unaffordable faction role pools must fall back to the matching global role pool'
    $GeneratorTests = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_generator.script')
    Assert-True ($GeneratorTests -match 'generator_primary_pool_affordability_falls_back') 'Generator tests must cover unaffordable non-empty faction primary pools'
    Assert-True ($Task3GeneratorContent -match 'value\.knife') 'Stable encoding must include the generated knife'
}
if (Test-Path -LiteralPath $DifficultyPath) {
    $DifficultyContent = Get-Content -LiteralPath $DifficultyPath -Raw
    foreach ($Difficulty in @('rookie', 'stalker', 'veteran', 'master')) {
        Assert-True ($DifficultyContent -match ("(?m)^\[ga_difficulty_" + $Difficulty + "\]\r?$")) "Difficulty catalog must include $Difficulty"
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
$GoldenPath = Join-Path $RepoRoot 'tests\fixtures\golden-fights-v3.txt'
if (Test-Path -LiteralPath $GoldenPath) {
    $GoldenContent = Get-Content -LiteralPath $GoldenPath -Raw
    Assert-True (([regex]::Matches($GoldenContent, '(?m)^seed=\d+,difficulty=(rookie|stalker|veteran|master),fight=\d+,stable_encode=schema_version=3\|.+\|diagnostic=FightSpecV3 .+$')).Count -eq 4) 'Golden fixture must contain four complete v3 stable encodings'
}

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
$ReadmePath = Join-Path $RepoRoot 'README.md'
if (Test-Path -LiteralPath $ReadmePath) {
    $ReadmeContent = Get-Content -LiteralPath $ReadmePath -Raw
    Assert-True ($ReadmeContent -match 'dev_test_autorun\s*=\s*true') 'README must document explicit in-game Dev-suite enablement'
    Assert-True ($ReadmeContent -match 'dev_test_autorun\s*=\s*false') 'README must document the production-like default'
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
        'docs\installation.md',
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

    $InstallationPath = Join-Path $RepoRoot 'docs\installation.md'
    if (Test-Path -LiteralPath $InstallationPath) {
        $InstallationContent = Get-Content -LiteralPath $InstallationPath -Raw
        foreach ($Marker in @(
            'Gamma Arena <version>',
            'one Gamma Arena version at a time',
            'exit an active Arena session',
            'keep the old mod folder for rollback',
            'never merge',
            'ordinary saves',
            'durable UI preferences',
            'not resumed across add-on versions'
        )) {
            Assert-True ($InstallationContent -match [regex]::Escape($Marker)) "Installation guide must state: $Marker"
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
}
$Task11DomainContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_domain.script') -Raw
Assert-True ($Task11DomainContent -match 'gamma_arena_test_tactical_director\.run\s*\(\s*run_case_fn\s*\)') 'Dev domain suite must execute tactical director tests'
$Task11AdapterTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_tactical_adapter.script'
Assert-True (Test-Path -LiteralPath $Task11AdapterTestPath) 'Tactical adapter dev suite is missing'
Assert-True ($Task11DomainContent -match 'gamma_arena_test_tactical_adapter\.run\s*\(\s*run_case_fn\s*\)') 'Dev domain suite must execute tactical adapter tests'
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
Assert-True ($Task11EntityContent -match 'tactical[\s\S]{0,1800}set_actor_hostile[\s\S]{0,1000}set_state\("ACTIVE"\)') 'Tactical bind must precede hostility and ACTIVE'
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
Assert-True ($Task12BootstrapContent -match 'gamma_arena_generator\.generate\(session,\s*fight_index,\s*catalog_snapshot,\s*resolved_layout\)') 'Bootstrap generator port must receive the resolved physical layout'
Assert-True ($Task12BootstrapContent -match 'gamma_arena_validator\.validate\(spec,\s*catalog_snapshot,\s*resolved_layout\)') 'Bootstrap validator port must receive the same resolved physical layout'
Assert-True ($Task12OrchestratorContent -match 'function\s+Orchestrator:prepare_fight\s*\([\s\S]{0,700}layout_snapshot\s*\([\s\S]{0,700}deps\.generator[\s\S]{0,300}layout\.value[\s\S]{0,500}deps\.validator[\s\S]{0,300}layout\.value') 'Fight preparation must thread one resolved layout through generation and validation'
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

foreach ($IntegrityMarker in @('VERTICAL_ESCAPE_GRACE_MS', 'EARLY_SELF_DEATH_WINDOW_MS', 'GA_FIGHT_INTEGRITY_FAILED', 'integrity_status', 'vertical_escape', 'early_self_death')) {
    Assert-True ($Task12EntityContent.Contains($IntegrityMarker)) "Arena integrity evidence is missing marker: $IntegrityMarker"
}
Assert-True ($Task12EntityContent.Contains('VICTORY_DEFEATED_STATES') -and $Task12EntityContent -match 'VICTORY_DEFEATED_STATES\[record\.terminal_state\]') 'Missing opponents must remain non-victory-qualified until integrity recovery starts'
foreach ($IntegrityMarker in @('MAX_INTEGRITY_RETRIES', 'integrity_retry', 'reconcile_active_integrity', 'GA_FIGHT_INTEGRITY_RETRY_EXHAUSTED')) {
    Assert-True ($Task12OrchestratorContent.Contains($IntegrityMarker)) "Arena integrity recovery is missing marker: $IntegrityMarker"
}
Assert-True ($Task12OrchestratorContent -match 'reconcile_active_integrity\s*\([\s\S]{0,500}reconcile_active_victory\s*\(') 'Integrity recovery must be reconciled before victory'
Assert-True ($Task12BootstrapContent.Contains('object_position')) 'Bootstrap must bind guarded opponent position evidence'
$Task13RuntimeTests = Get-Content -LiteralPath (Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script') -Raw
foreach ($IntegrityTest in @('runtime_entity_vertical_escape_requires_grace', 'runtime_entity_missing_is_integrity_not_victory', 'runtime_entity_early_self_death_is_integrity', 'runtime_orchestrator_integrity_retries_same_spec_twice', 'runtime_orchestrator_integrity_retry_exhaustion_fails', 'runtime_entity_cleanup_retires_vanished_owned_child')) {
    Assert-True ($Task13RuntimeTests.Contains($IntegrityTest)) "Runtime integrity suite is missing case: $IntegrityTest"
}

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

Write-Host 'PASS: static project checks passed'
