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

$Task2RunnerPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runner.script'
$Task2LogPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_log.script'
$Task2RngPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_rng.script'
if (Test-Path -LiteralPath $Task2RunnerPath) {
    $Task2RunnerContent = Get-Content -LiteralPath $Task2RunnerPath -Raw
    Assert-True ($Task2RunnerContent -match '(?s)pcall\s*\(\s*function\s*\(\s*\)\s*return\s+gamma_arena_test_domain\.run\s*\(\s*run_case\s*\)\s*end\s*\)') 'Dev test runner must resolve and execute the domain suite inside pcall'
}
if (Test-Path -LiteralPath $Task2LogPath) {
    $Task2LogContent = Get-Content -LiteralPath $Task2LogPath -Raw
    Assert-True ($Task2LogContent -match 'sort_key\s*=\s*type\s*\(\s*key\s*\)\s*\.\.\s*":"') 'Logger must use a type-aware canonical context sort key'
    Assert-True ($Task2LogContent -match '(?s)left\.sort_key\s*==\s*right\.sort_key') 'Logger must use a total context sort comparator'
    Assert-True ($Task2LogContent -match 'pcall\s*\(\s*printf\s*,') 'Logger must protect the printf sink with pcall'
}
if (Test-Path -LiteralPath $Task2RngPath) {
    $Task2RngContent = Get-Content -LiteralPath $Task2RngPath -Raw
    Assert-True ($Task2RngContent -match 'minimum\s*~=\s*minimum') 'RNG must reject NaN minimum bounds'
    Assert-True ($Task2RngContent -match 'maximum\s*~=\s*maximum') 'RNG must reject NaN maximum bounds'
    Assert-True ($Task2RngContent -match 'math\.huge') 'RNG must reject infinite bounds and spans'
    Assert-True ($Task2RngContent -match 'local\s+span\s*=\s*maximum\s*-\s*minimum\s*\+\s*1') 'RNG must validate its computed span before modulo'
}

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

Write-Host 'PASS: static project checks passed'
