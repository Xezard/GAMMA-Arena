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

$Task4ScriptContracts = @(
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_config_tx.script'; Namespace = 'gamma_arena_config_tx'; Required = @('(?m)^function\s+run\s*\(', '(?m)^function\s+snapshot\s*\(', '(?m)^function\s+recover\s*\(', '(?m)^function\s+is_quarantined\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_migrations.script'; Namespace = 'gamma_arena_migrations'; Required = @('(?m)^function\s+migrate\s*\(', '(?m)^function\s+read_settings\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_session_store.script'; Namespace = 'gamma_arena_session_store'; Required = @('(?m)^function\s+new_store\s*\(', '(?m)^function\s+parse_manual_seed\s*\(', '(?m)^function\s+validate_start_request\s*\(', '(?m)^function\s+random_session_seed\s*\(', '(?m)^function\s+save_preferences\s*\(', '(?m)^function\s+issue_launch\s*\(', '(?m)^function\s+parse_launch_token\s*\(', '(?m)^function\s+consume_launch\s*\(', '(?m)^function\s+issue_resume\s*\(', '(?m)^function\s+consume_resume\s*\(', '(?m)^function\s+write_character_creation\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\modxml_gamma_arena.script'; Namespace = 'modxml_gamma_arena'; Required = @('(?m)^function\s+on_xml_read\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_main_menu.script'; Namespace = 'gamma_arena_main_menu'; Required = @('(?m)^function\s+on_game_start\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_ui_start.script'; Namespace = 'gamma_arena_ui_start'; Required = @('class\s+"UIStart"\s+\(CUIScriptWnd\)', '(?m)^function\s+create\s*\(', '(?m)^function\s+show_fatal\s*\(') },
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
    Assert-True ($ConfigTxContent -match 'local function _snapshot_unchecked') 'Transactions must use a private unchecked snapshot only after their quarantine guard'
    Assert-True ($ConfigTxContent -match '(?s)function snapshot\s*\(\s*config\s*,\s*section\s*,\s*keys\s*\)\s*if is_quarantined\s*\(\s*config\s*\)') 'The public config snapshot API must reject quarantined configs'
}

$StorePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script'
if (Test-Path -LiteralPath $StorePath) {
    $StoreContent = Get-Content -LiteralPath $StorePath -Raw
    Assert-True ($StoreContent -match 'LAUNCH_TOKEN_TTL\s*=\s*600') 'Launch token TTL must be 600 seconds'
    Assert-True ($StoreContent -match 'ga1:') 'Launch token must use the ga1:<epoch>:<nonce> grammar'
    Assert-True ($StoreContent -match 'volatile_launch_permits') 'Launch activation must require a process-local volatile permit'
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
    Assert-True ($StoreContent -match 'GA_RESUME_ALREADY_PENDING') 'Session store must not overwrite a pending resume intent'
    Assert-True (([regex]::Matches($StoreContent, 'GA_INTENT_CONFLICT')).Count -ge 4) 'Launch/resume issuance and consumption must reject intent conflicts'
    Assert-True ($ConfigTxContent -match 'remove_line') 'Transient and optional character-creation keys must use transactional remove_line operations'
    Assert-True ($StoreContent -notmatch '\btime_global\b') 'Session store must use injected wall-clock/os.time instead of time_global'
    Assert-True ($StoreContent -notmatch '(?is)\bw_value\s*\([^\)]*,\s*nil\s*\)') 'Session store must never use w_value(..., nil)'
    foreach ($Key in @('launch_pending','launch_token','launch_mode_id','launch_difficulty_id','launch_seed_mode','launch_session_seed','resume_pending','resume_session_id','resume_session_nonce','resume_next_fight_index','resume_checkpoint_name','resume_schema_version')) {
        Assert-True ($StoreContent -match [regex]::Escape($Key)) "Session store must cover transient key $Key"
    }
    foreach ($Key in @('new_game_difficulty','new_game_economy','new_game_economy_treasure','new_game_character_name','new_game_faction','new_game_map','new_game_money','new_game_loadout','new_game_story_mode','new_game_icon','new_game_hardcore_mode','new_game_hardcore_mode_lives','new_game_hardcore_mode_regenerate','new_game_survival_mode','new_game_azazel_mode','new_game_warfare','new_game_campfire_mode','new_game_conditions_mode','new_game_timer_mode','new_game_opened_routes','new_game_test')) {
        Assert-True ($StoreContent -match [regex]::Escape($Key)) "Character-creation bridge must cover $Key"
    }
}

$DxmlPath = Join-Path $RepoRoot 'src\gamedata\scripts\modxml_gamma_arena.script'
if (Test-Path -LiteralPath $DxmlPath) {
    $DxmlContent = Get-Content -LiteralPath $DxmlPath -Raw
    Assert-True ($DxmlContent -match 'RegisterScriptCallback\s*\(\s*"on_xml_read"') 'DXML module must register on_xml_read from its zero-argument registrar'
    Assert-True ($DxmlContent -match 'ui\\\\ui_mm_main\.xml') 'DXML handler must accept the canonical full callback path ui\ui_mm_main.xml'
    Assert-True ($DxmlContent -match 'string\.lower') 'DXML handler must normalize callback path case minimally'
    Assert-True ($DxmlContent -match 'string\.gsub') 'DXML handler must normalize callback path separators minimally'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main btn\[name=btn_gamma_arena\]"\s*\)') 'DXML handler must query the exact duplicate guard selector'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main"\s*\)') 'DXML handler must feature-probe menu_main'
    Assert-True (([regex]::Matches($DxmlContent, '<btn name="btn_gamma_arena" caption="st_gamma_arena_main_menu"\s*/>')).Count -eq 1) 'DXML module must contain exactly one Arena button insertion'
    Assert-True ($DxmlContent -match 'insertFromXMLString') 'DXML handler must insert through insertFromXMLString'
    Assert-True ($DxmlContent -match 'pcall\s*\(\s*gamma_arena_log\.error') 'DXML callback must internally log structured failures because callback returns are ignored'
}

$Task4DevTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_migrations.script'
if (Test-Path -LiteralPath $Task4DevTestPath) {
    $Task4DevTestContent = Get-Content -LiteralPath $Task4DevTestPath -Raw
    foreach ($Marker in @('stale_launch_is_recovered_by_new_store','same_store_corrupt_launch_is_replaced','resume_rejects_tampered_expected_session','mutation_failure_matrix_is_crash_safe','recovery_failure_quarantines_transaction','read_and_false_return_faults_are_safe','stale_cleanup_and_conflict_faults_are_safe','matching_resume_cleanup_is_session_scoped','dxml_accepts_canonical_callback_path','arm_fault','arm_read_fault','arm_recovery_fault','persisted')) {
        Assert-True ($Task4DevTestContent -match $Marker) "Task 4 Dev tests must cover $Marker"
    }
}

$MainMenuPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_main_menu.script'
if (Test-Path -LiteralPath $MainMenuPath) {
    $MainMenuContent = Get-Content -LiteralPath $MainMenuPath -Raw
    Assert-True ($MainMenuContent -match 'RegisterScriptCallback\s*\(\s*"main_menu_on_init"') 'Main-menu adapter must bind through main_menu_on_init'
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
}

$UiXmlPath = Join-Path $RepoRoot 'src\gamedata\configs\ui\gamma_arena_start.xml'
if (Test-Path -LiteralPath $UiXmlPath) {
    [xml]$UiXml = Get-Content -LiteralPath $UiXmlPath -Raw
    foreach ($Id in @('gamma_arena_start','title','difficulty','seed','random_seed','validation','start','back','fatal','fatal_text','fatal_main_menu')) {
        Assert-True ($null -ne $UiXml.SelectSingleNode("//*[local-name()='$Id']")) "Start UI XML is missing control $Id"
    }
    Assert-True (@($UiXml.SelectNodes("//*[local-name()='fatal']/*[local-name()='fatal_main_menu']")).Count -eq 1) 'Fatal UI must contain exactly one main-menu action'
}

foreach ($Locale in @('rus','eng')) {
    $LocalePath = Join-Path $RepoRoot "src\gamedata\configs\text\$Locale\st_gamma_arena.xml"
    if (Test-Path -LiteralPath $LocalePath) {
        [xml]$LocaleXml = Get-Content -LiteralPath $LocalePath -Raw
        $MenuNode = $LocaleXml.SelectSingleNode('//string[@id="st_gamma_arena_main_menu"]/text')
        Assert-True ($null -ne $MenuNode -and $MenuNode.InnerText -ceq 'ARENA') "$Locale main-menu caption must be exactly ARENA"
        foreach ($Id in @('st_gamma_arena_title','st_gamma_arena_difficulty_rookie','st_gamma_arena_difficulty_stalker','st_gamma_arena_difficulty_veteran','st_gamma_arena_difficulty_master','st_gamma_arena_random_seed','st_gamma_arena_start','st_gamma_arena_back','st_gamma_arena_fatal_title','st_gamma_arena_fatal_error_line','st_gamma_arena_fatal_main_menu','st_gamma_arena_seed_invalid','st_gamma_arena_manual_save_disabled')) {
            Assert-True ($null -ne $LocaleXml.SelectSingleNode("//string[@id='$Id']/text")) "$Locale localization is missing $Id"
        }
    }
}

$RussianLocalePath = Join-Path $RepoRoot 'src\gamedata\configs\text\rus\st_gamma_arena.xml'
if (Test-Path -LiteralPath $RussianLocalePath) {
    [xml]$RussianXml = Get-Content -LiteralPath $RussianLocalePath -Raw -Encoding UTF8
    $RussianContent = (@($RussianXml.SelectNodes('//text')) | ForEach-Object { $_.InnerText }) -join "`n"
    $RussianExpected = @(
        (ConvertFrom-Json '"\u041d\u043e\u0432\u0438\u0447\u043e\u043a"'),
        (ConvertFrom-Json '"\u0421\u0442\u0430\u043b\u043a\u0435\u0440"'),
        (ConvertFrom-Json '"\u0412\u0435\u0442\u0435\u0440\u0430\u043d"'),
        (ConvertFrom-Json '"\u041c\u0430\u0441\u0442\u0435\u0440"'),
        ((ConvertFrom-Json '"\u0421\u043b\u0443\u0447\u0430\u0439\u043d\u044b\u0439"') + ' seed'),
        (ConvertFrom-Json '"\u041d\u0410\u0427\u0410\u0422\u042c"'),
        (ConvertFrom-Json '"\u041d\u0410\u0417\u0410\u0414"'),
        (ConvertFrom-Json '"\u0412 \u0433\u043b\u0430\u0432\u043d\u043e\u0435 \u043c\u0435\u043d\u044e"')
    )
    foreach ($Text in $RussianExpected) {
        Assert-True ($RussianContent.Contains($Text)) "Russian localization must contain exact UTF-8 text: $Text"
    }
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
    foreach ($Marker in @('invoke_callback','new_registrar','register_all','UnregisterScriptCallback','GA_BOOTSTRAP_REGISTRATION_POISONED','rollback')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Bootstrap hardening must cover $Marker"
    }
    Assert-True ($Task5BootstrapContent -match 'pcall') 'Bootstrap callbacks must contain exceptions'
    Assert-True ($Task5BootstrapContent -match 'if\s+not\s+active\s+then\s+return\s+end') 'Inactive runtime-effect callbacks must return before delegation'
    Assert-True ($Task5BootstrapContent -match 'result\.ok\s*==\s*false') 'Bootstrap boundary must route structured Result failures'
    Assert-True ($Task5BootstrapContent -match 'return\s+callback\(\)') 'Bootstrap fatal UI closure must propagate main-menu action results'
}

$Task5CompatPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script'
if (Test-Path -LiteralPath $Task5CompatPath) {
    $Task5CompatContent = Get-Content -LiteralPath $Task5CompatPath -Raw
    foreach ($Capability in @('RegisterScriptCallback','UnregisterScriptCallback','ini_file','system_ini','alife','alife_create','alife_create_item','alife_release_id','getFS','se_save_var','level.patrol_path_exists','patrol','db.actor','axr_main.config','safe_release_manager.release')) {
        Assert-True ($Task5CompatContent -match [regex]::Escape($Capability)) "Preflight must probe $Capability"
    }
    foreach ($Marker in @('l05_bar','AI_STL_S','bandit','point','level_vertex_id','game_vertex_id','4294967295','GA_PREFLIGHT_PATROL_MISSING','GA_PREFLIGHT_PATROL_INVALID','GA_PREFLIGHT_SECTION_MISSING','GA_NPC_CLASS_API_MISSING','GA_NPC_CLASS_MISSING','GA_NPC_CLASS_READ_FAILED','GA_NPC_CLASS_INVALID','GA_NPC_COMMUNITY_API_MISSING','GA_NPC_COMMUNITY_MISSING','GA_NPC_COMMUNITY_READ_FAILED','GA_NPC_COMMUNITY_INVALID')) {
        Assert-True ($Task5CompatContent -match [regex]::Escape($Marker)) "Preflight must enforce $Marker"
    }
}

$Task5OrchestratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_orchestrator.script'
if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    $Task5OrchestratorContent = Get-Content -LiteralPath $Task5OrchestratorPath -Raw
    foreach ($Marker in @('inspect_intents','consume_launch','prepare_resume','gamma_arena_session','st_gamma_arena_manual_save_disabled','expect_checkpoint_reload','GA_INTENT_CONFLICT','GA_LAUNCH_REQUIRES_NEW_GAME','disconnect','pending_load_state','awaiting_activation','on_callback_result_error','GA_DISCONNECT_FAILED','main_menu_executed')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Orchestrator must cover $Marker"
    }
    foreach ($Forbidden in @('FightSpec','FightRegistry','math.random','math.randomseed')) {
        Assert-True ($Task5OrchestratorContent -notmatch [regex]::Escape($Forbidden)) "Task 5 orchestrator must not contain $Forbidden"
    }
}

$Task5StorePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script'
if (Test-Path -LiteralPath $Task5StorePath) {
    $Task5StoreContent = Get-Content -LiteralPath $Task5StorePath -Raw
    Assert-True ($Task5StoreContent -match 'GA_SESSION_UNKNOWN_FIELD') 'ArenaSession validator must reject unknown/future fields'
    Assert-True ($Task5StoreContent -match 'function Store:inspect_intents') 'Session store must expose non-mutating intent inspection'
    Assert-True ($Task5StoreContent -match 'function Store:prepare_resume') 'Session store must validate a resume route before checkpoint re-hide'
    Assert-True ($Task5StoreContent -match 'function Store:clear_resume_if_matches') 'Checkpoint cleanup must clear only a ResumeIntent bound to its ArenaSession'
}

$Task5DevTestPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script'
if (Test-Path -LiteralPath $Task5DevTestPath) {
    $Task5DevTestContent = Get-Content -LiteralPath $Task5DevTestPath -Raw
    foreach ($Marker in @('runtime_preflight_aggregates_in_stable_order','runtime_preflight_requires_task6_actor_checkpoint_ports','runtime_preflight_requires_community_for_every_custom_profile','runtime_preflight_requires_human_class_for_every_custom_profile','runtime_preflight_rejects_missing_profile_value_apis','runtime_preflight_normalizes_effective_bandit_community','runtime_wrong_level_skips_patrol_resolution','runtime_launch_consumes_before_preflight_once','runtime_activation_requires_game_load_boundary','runtime_invalid_or_expired_launch_never_reaches_preflight','runtime_ordinary_loaded_save_rejects_stray_launch','runtime_ordinary_loaded_save_rejects_stray_resume','runtime_new_game_does_not_reuse_prior_load_state_latch','runtime_game_load_boundary_drops_prior_runtime_generation','runtime_config_quarantine_propagates_to_fatal','runtime_save_payload_is_plain_deep_copy','runtime_manual_save_and_load_flags_are_blocked','runtime_callback_boundary_routes_exceptions_once','runtime_callback_boundary_routes_false_results_once','runtime_inactive_callback_results_remain_benign','runtime_active_save_failure_enters_fatal_once','runtime_fatal_main_menu_retries_throw_then_becomes_idempotent','runtime_fatal_main_menu_retries_explicit_false','runtime_fatal_ui_helper_propagates_callback_results','runtime_bootstrap_registration_rolls_back_every_position','runtime_bootstrap_registration_poison_blocks_retry','runtime_bootstrap_requires_unregister_before_composition','runtime_net_destroy_teardown_honors_checkpoint_latch','runtime_unexpected_net_destroy_clears_external_route')) {
        Assert-True ($Task5DevTestContent -match $Marker) "Task 5 Dev tests must cover $Marker"
    }
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
    foreach ($Marker in @('normalize_for_checkpoint','verify_inventory_empty','apply_loadout','reset_after_victory','hold_after_logical_death','begin_update','iterate_inventory','parent_id','release_item_id','set_health_ex','set_power','set_radiation','set_bleeding','set_psy_health','give_money','disable_effects_timer','set_actor_position','set_actor_direction','input_owned','GA_ACTOR_INACTIVE')) {
        Assert-True ($Task6ActorContent -match [regex]::Escape($Marker)) "Actor adapter must cover $Marker"
    }
    Assert-True ($Task6ActorContent -match '"set_bleeding"\s*,\s*1') 'GAMMA actor normalization must use the observed cured bleeding sentinel 1'
}

$Task6CheckpointPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_checkpoint_adapter.script'
if (Test-Path -LiteralPath $Task6CheckpointPath) {
    $Task6CheckpointContent = Get-Content -LiteralPath $Task6CheckpointPath -Raw
    foreach ($Marker in @('WAITING_STABLE','HIDING','READY','UNHIDING','LOADING','REHIDING','CLEANING','_gamma_arena_checkpoint','.scop','.scoc','.dds','.gamma_arena_hidden','GA_CHECKPOINT_TIMEOUT','GA_CHECKPOINT_UNSAFE_PATH','issue_resume','consume_resume','clear_resume_if_matches','pending_or_timeout','elapsed_ms','engine_fs_port','update_path','file_rename','file_delete','"rb"','save " .. CHECKPOINT_NAME','load " .. CHECKPOINT_NAME')) {
        Assert-True ($Task6CheckpointContent -match [regex]::Escape($Marker)) "Checkpoint adapter must cover $Marker"
    }
    foreach ($Forbidden in @('file_list','file_list_open_ex','file_find')) {
        Assert-True ($Task6CheckpointContent -notmatch [regex]::Escape($Forbidden)) "Checkpoint adapter must not use broad path discovery: $Forbidden"
    }
}

if (Test-Path -LiteralPath $Task5BootstrapPath) {
    foreach ($Marker in @('gamma_arena_actor_adapter.new','gamma_arena_checkpoint_adapter.new','level.disable_input','level.enable_input','safe_release_manager.release')) {
        Assert-True ($Task5BootstrapContent -match [regex]::Escape($Marker)) "Task 6 bootstrap composition must cover $Marker"
    }
}

$Task6CompatPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script'
if (Test-Path -LiteralPath $Task6CompatPath) {
    $Task6CompatContent = Get-Content -LiteralPath $Task6CompatPath -Raw
    foreach ($Marker in @('getFS.update_path','getFS.file_rename','getFS.file_delete','exec_console_cmd','time_global','level.disable_input','level.enable_input','db.actor.iterate_inventory','db.actor.set_bleeding','db.actor.set_actor_position')) {
        Assert-True ($Task6CompatContent -match [regex]::Escape($Marker)) "Task 6 preflight must require $Marker"
    }
}

if (Test-Path -LiteralPath $Task5OrchestratorPath) {
    foreach ($Marker in @('normalize_for_checkpoint','verify_inventory_empty','checkpoint','request_checkpoint_restore','runtime_stage')) {
        Assert-True ($Task5OrchestratorContent -match [regex]::Escape($Marker)) "Task 6 orchestration must cover $Marker"
    }
    Assert-True ($Task5OrchestratorContent -notmatch 'gamma_arena_generator') 'FightSpec generation must remain gated out of Task 6'
}

if (Test-Path -LiteralPath $Task5DevTestPath) {
    foreach ($Marker in @('runtime_actor_inventory_release_is_deferred_and_verified','runtime_actor_normalization_uses_gamma_bleeding_sentinel','runtime_actor_input_ownership_is_idempotent','runtime_actor_rejects_coincident_patrol_points','runtime_checkpoint_requires_stable_required_files','runtime_checkpoint_allows_absent_or_late_dds','runtime_checkpoint_wrap_clock_times_out','runtime_checkpoint_verifies_rename_and_delete_postconditions','runtime_checkpoint_recovers_mixed_crash_states','runtime_checkpoint_persists_intent_before_load','runtime_checkpoint_consumes_intent_only_after_rehide','runtime_checkpoint_rejects_mismatched_resume','runtime_checkpoint_cleanup_is_idempotent_in_every_state','runtime_checkpoint_two_sessions_leave_no_stale_paths','runtime_checkpoint_ready_gates_generation')) {
        Assert-True ($Task5DevTestContent -match [regex]::Escape($Marker)) "Task 6 Dev tests must cover $Marker"
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
    Assert-True ($Task3ValidatorContent -match 'GA_ENEMY_SLOT_BUDGET_INVALID') 'Validator must enforce deterministic per-slot enemy budgets'
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

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

Write-Host 'PASS: static project checks passed'
