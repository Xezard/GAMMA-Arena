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
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_migrations.script'; Namespace = 'gamma_arena_migrations'; Required = @('(?m)^function\s+migrate\s*\(', '(?m)^function\s+read_settings\s*\(') },
    [PSCustomObject]@{ Path = 'src\gamedata\scripts\gamma_arena_session_store.script'; Namespace = 'gamma_arena_session_store'; Required = @('(?m)^function\s+parse_manual_seed\s*\(', '(?m)^function\s+validate_start_request\s*\(', '(?m)^function\s+random_session_seed\s*\(', '(?m)^function\s+save_preferences\s*\(', '(?m)^function\s+issue_launch\s*\(', '(?m)^function\s+parse_launch_token\s*\(', '(?m)^function\s+consume_launch\s*\(', '(?m)^function\s+issue_resume\s*\(', '(?m)^function\s+consume_resume\s*\(', '(?m)^function\s+write_character_creation\s*\(') },
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
}

$StorePath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_session_store.script'
if (Test-Path -LiteralPath $StorePath) {
    $StoreContent = Get-Content -LiteralPath $StorePath -Raw
    Assert-True ($StoreContent -match 'LAUNCH_TOKEN_TTL\s*=\s*600') 'Launch token TTL must be 600 seconds'
    Assert-True ($StoreContent -match 'ga1:') 'Launch token must use the ga1:<epoch>:<nonce> grammar'
    Assert-True ($StoreContent -match 'volatile_launch_permits') 'Launch activation must require a process-local volatile permit'
    Assert-True ($StoreContent -match 'GA_RESUME_ALREADY_PENDING') 'Session store must not overwrite a pending resume intent'
    Assert-True (([regex]::Matches($StoreContent, 'GA_INTENT_CONFLICT')).Count -ge 4) 'Launch/resume issuance and consumption must reject intent conflicts'
    Assert-True ($StoreContent -match 'remove_line') 'Transient and optional character-creation keys must use remove_line'
    Assert-True ($StoreContent -notmatch '\btime_global\b') 'Session store must use injected wall-clock/os.time instead of time_global'
    Assert-True ($StoreContent -notmatch '(?is)\bw_value\s*\([^\)]*,\s*nil\s*\)') 'Session store must never use w_value(..., nil)'
    foreach ($Key in @('launch_pending','launch_token','launch_mode_id','launch_difficulty_id','launch_seed_mode','launch_session_seed','resume_pending','resume_session_id','resume_session_nonce','resume_next_fight_index','resume_checkpoint_name','resume_schema_version')) {
        Assert-True ($StoreContent -match [regex]::Escape($Key)) "Session store must cover transient key $Key"
    }
    foreach ($Key in @('new_game_difficulty','new_game_economy','new_game_character_name','new_game_faction','new_game_map','new_game_money','new_game_loadout','new_game_story_mode')) {
        Assert-True ($StoreContent -match [regex]::Escape($Key)) "Character-creation bridge must cover $Key"
    }
}

$DxmlPath = Join-Path $RepoRoot 'src\gamedata\scripts\modxml_gamma_arena.script'
if (Test-Path -LiteralPath $DxmlPath) {
    $DxmlContent = Get-Content -LiteralPath $DxmlPath -Raw
    Assert-True ($DxmlContent -match 'RegisterScriptCallback\s*\(\s*"on_xml_read"') 'DXML module must register on_xml_read from its zero-argument registrar'
    Assert-True ($DxmlContent -match 'xml_file_name\s*~=\s*"ui_mm_main\.xml"') 'DXML handler must ignore every file except ui_mm_main.xml'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main btn\[name=btn_gamma_arena\]"\s*\)') 'DXML handler must query the exact duplicate guard selector'
    Assert-True ($DxmlContent -match 'query\s*\(\s*"menu_main"\s*\)') 'DXML handler must feature-probe menu_main'
    Assert-True (([regex]::Matches($DxmlContent, '<btn name="btn_gamma_arena" caption="st_gamma_arena_main_menu"\s*/>')).Count -eq 1) 'DXML module must contain exactly one Arena button insertion'
    Assert-True ($DxmlContent -match 'insertFromXMLString') 'DXML handler must insert through insertFromXMLString'
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
        foreach ($Id in @('st_gamma_arena_title','st_gamma_arena_difficulty_rookie','st_gamma_arena_difficulty_stalker','st_gamma_arena_difficulty_veteran','st_gamma_arena_difficulty_master','st_gamma_arena_random_seed','st_gamma_arena_start','st_gamma_arena_back','st_gamma_arena_fatal_title','st_gamma_arena_fatal_error_line','st_gamma_arena_fatal_main_menu','st_gamma_arena_seed_invalid')) {
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
