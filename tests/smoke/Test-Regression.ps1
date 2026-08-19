[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:Failures = New-Object System.Collections.Generic.List[string]
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gamma-arena-regression-" + [Guid]::NewGuid().ToString('N'))

& (Join-Path $RepoRoot 'tests\reference\New-GammaArenaGoldenFights.ps1') -Verify
if (-not $?) { exit 1 }

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        $script:Failures.Add($Message)
    }
}

function Write-FixtureFile([string]$Root, [string]$RelativePath, [string]$Content = '') {
    $Path = Join-Path $Root $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function New-StaticFixture([string]$Name) {
    $Root = Join-Path $TempRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $Root 'src\gamedata') -Force | Out-Null
    foreach ($File in @('VERSION', '.gitattributes', '.gitignore', 'README.md', 'CHANGELOG.md')) {
        Write-FixtureFile $Root $File 'fixture'
    }
    return $Root
}

function Add-Task2ContractFixture([string]$Root) {
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_assert.script' @'
function equals() end
function is_true() end
function is_false() end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_runner.script' @'
function run_case() end
function on_game_start()
    return pcall(function()
        return gamma_arena_test_domain.run(run_case)
    end)
end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_domain.script' @'
function run() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_result.script' @'
function ok() end
function err() end
function is_ok() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_log.script' @'
local function canonical_key(key)
    local key_type = type(key)
    if key_type == "string" then return "string:" .. key end
    if key_type == "number" then return "number:" .. key end
    if key_type == "boolean" then return "boolean:" .. key end
end
local entries = {}
local seen_keys = {}
for key, value in pairs({}) do
    local canonical = canonical_key(key)
    local existing_index = canonical and seen_keys[canonical]
    if existing_index then
        entries[existing_index].value = "<canonical-key-collision>"
    elseif canonical then
        seen_keys[canonical] = #entries + 1
        entries[#entries + 1] = { key = canonical, value = value }
    end
end
table.sort(entries, function(left, right)
    return left.key < right.key
end)
pcall(printf, "fixture")
function info() end
function warn() end
function error() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_rng.script' @'
function normalize_uint32(seed)
    local value = tonumber(seed) or 0
    if value ~= value or value == math.huge or value == -math.huge then
        return 1
    end
    return 1
end
function derive_seed() end
function new()
    local function next_int(minimum, maximum)
        if minimum ~= minimum or maximum ~= maximum or minimum == math.huge or maximum == math.huge then
            return nil
        end
        local span = maximum - minimum + 1
        return span
    end
    return { next_int = next_int }
end
function random_session_seed() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_state_machine.script' @'
states = {}
events = {}
function transition() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_catalog.script' @'
function load()
    local markers = "GA_DIFFICULTY_BUDGET_INFEASIBLE GA_CATALOG_SECTION_CHECK_FAILED GA_CATALOG_UNKNOWN_SECTION section_for_each line_count r_line"
    return markers
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_mode_skirmish.script' @'
function id() end
function difficulty_envelope() end
function next_fight_index() end
function validate_session() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_generator.script' @'
function generate() end
function stable_encode() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_validator.script' @'
function validate()
    return "GA_MODE_INVALID GA_LEVEL_INVALID GA_LAYOUT_VERSION_INVALID GA_OPPONENT_SLOT_INVALID GA_FIGHT_ID_INVALID GA_FIGHTSPEC_TYPE_INVALID"
end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_generator.script' 'function run() end'
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx' @'
[meta]
schema_version = 1
revision = 1
gamma_arena_bandit_novice
gamma_arena_bandit_trainee
gamma_arena_bandit_experienced
gamma_arena_bandit_veteran
[outfit_novice]
section = novice_outfit
cost = 1
'@
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx' @'
[ga_difficulty_rookie]
[ga_difficulty_stalker]
[ga_difficulty_veteran]
[ga_difficulty_master]
'@
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx' @'
[ga_layout_rostok_arena_v1]
level = l05_bar
opponent_spawn_paths = bar_arena_walk_3_1,bar_arena_walk_3_2,bar_arena_walk_6_1,bar_arena_walk_6_3,bar_arena_walk_6_6,bar_arena_monstr_walk
'@
    Write-FixtureFile $Root 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx' @'
[gamma_arena_bandit_novice]:sim_default_bandit_0
[gamma_arena_bandit_veteran]:sim_default_bandit_3
'@
    Write-FixtureFile $Root 'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx' @'
![skip_npcs]
gamma_arena_bandit_novice = bandit
gamma_arena_bandit_trainee = bandit
gamma_arena_bandit_experienced = bandit
gamma_arena_bandit_veteran = bandit
'@
    Write-FixtureFile $Root 'tests\fixtures\golden-fights-v1.txt' @'
seed=0,difficulty=rookie,fight=0,stable_encode=schema_version=1|fight_id=ga-1-0-g1-c1-l1|diagnostic=FightSpecV1 rookie
seed=1,difficulty=stalker,fight=0,stable_encode=schema_version=1|fight_id=ga-1-0-g1-c1-l1|diagnostic=FightSpecV1 stalker
seed=3735928559,difficulty=veteran,fight=7,stable_encode=schema_version=1|fight_id=ga-1588444913-7-g1-c1-l1|diagnostic=FightSpecV1 veteran
seed=4294967295,difficulty=master,fight=31,stable_encode=schema_version=1|fight_id=ga-3-31-g1-c1-l1|diagnostic=FightSpecV1 master
'@
    Write-FixtureFile $Root 'schemas\fight-spec-v1.md' 'fixture'
}

function Invoke-PowerShellFile([string]$Path, [string[]]$Arguments) {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    $ErrorActionPreference = $PreviousErrorActionPreference
    return $ExitCode
}

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    $DevFixture = New-StaticFixture 'dev-fixture'
    Add-Task2ContractFixture $DevFixture
    Write-FixtureFile $DevFixture 'dev\gamedata\scripts\gamma_arena_test_dev.script' 'dev fixture'
    $DevFixtureExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DevFixture)
    Assert-True ($DevFixtureExit -eq 0) 'Static release policy must ignore dev/gamedata gamma_arena_test_* fixtures.'

    $NestedGammaRandomFixture = New-StaticFixture 'nested-gamma-random'
    Add-Task2ContractFixture $NestedGammaRandomFixture
    Write-FixtureFile $NestedGammaRandomFixture 'src\gamedata\scripts\nested\gamma_arena_random.script' 'local value = math.random()'
    $NestedGammaRandomExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NestedGammaRandomFixture)
    Assert-True ($NestedGammaRandomExit -ne 0) 'Static policy must reject a nested gamma_arena_* math.random call.'

    $NestedGaRandomFixture = New-StaticFixture 'nested-ga-random'
    Add-Task2ContractFixture $NestedGaRandomFixture
    Write-FixtureFile $NestedGaRandomFixture 'src\gamedata\scripts\nested\ga_random.script' 'local value = math.randomseed(7)'
    $NestedGaRandomExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NestedGaRandomFixture)
    Assert-True ($NestedGaRandomExit -ne 0) 'Static policy must reject a nested ga_* math.randomseed call.'

    $PrefixedMutantCatalogFixture = New-StaticFixture 'prefixed-mutant-catalog'
    Add-Task2ContractFixture $PrefixedMutantCatalogFixture
    Write-FixtureFile $PrefixedMutantCatalogFixture 'src\gamedata\configs\gamma_arena\arena_population.ltx' 'sim_default_bloodsucker = 1'
    $PrefixedMutantCatalogExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PrefixedMutantCatalogFixture)
    Assert-True ($PrefixedMutantCatalogExit -ne 0) 'Static policy must reject prefixed mutant class tokens in Arena configs.'

    $PositiveOnlyDxmlFixture = New-StaticFixture 'positive-only-dxml'
    Add-Task2ContractFixture $PositiveOnlyDxmlFixture
    Write-FixtureFile $PositiveOnlyDxmlFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert></dxml>'
    $PositiveOnlyDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PositiveOnlyDxmlFixture)
    Assert-True ($PositiveOnlyDxmlExit -ne 0) 'Static policy must reject a positive-only DXML duplicate query.'

    $MixedDxmlFixture = New-StaticFixture 'mixed-dxml'
    Add-Task2ContractFixture $MixedDxmlFixture
    Write-FixtureFile $MixedDxmlFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if not menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert><insert>add("btn_gamma_arena")</insert></dxml>'
    $MixedDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MixedDxmlFixture)
    Assert-True ($MixedDxmlExit -ne 0) 'Static policy must reject an unsafe DXML insert even when another insert is guarded.'

    $ValidStaticFixture = New-StaticFixture 'valid-static-fixture'
    Add-Task2ContractFixture $ValidStaticFixture
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\scripts\nested\gamma_arena_safe.script' 'local value = 4'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\scripts\nested\ga_safe.script' 'local value = 8'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\configs\gamma_arena\arena_population.ltx' 'sim_default_stalker = 1'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if not menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert></dxml>'
    $ValidStaticExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $ValidStaticFixture)
    Assert-True ($ValidStaticExit -eq 0) 'Static policy must accept deterministic gamma_arena_/ga_ scripts, a human Arena config, and a guarded DXML insert.'

    $MissingTask2Fixture = New-StaticFixture 'missing-task2-contract'
    Add-Task2ContractFixture $MissingTask2Fixture
    Remove-Item -LiteralPath (Join-Path $MissingTask2Fixture 'src\gamedata\scripts\gamma_arena_rng.script') -Force
    $MissingTask2Exit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingTask2Fixture)
    Assert-True ($MissingTask2Exit -ne 0) 'Static policy must reject a missing required Task 2 contract script.'

    $OutsideReleaseOutput = Join-Path $TempRoot 'outside-release-output'
    $ReleaseOutputExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Build-GammaArena.ps1') @('-Configuration', 'Release', '-OutputDirectory', $OutsideReleaseOutput)
    Assert-True ($ReleaseOutputExit -ne 0) 'Release build must reject an output directory outside <RepoRoot>\dist.'

    $TerminalFailureLog = Join-Path $TempRoot 'terminal-failure.log'
    [IO.File]::WriteAllText($TerminalFailureLog, "[GammaArenaTest] START`r`n[GammaArenaTest] ALL PASS`r`n[GammaArenaTest] SUITE FAILED`r`n", (New-Object Text.UTF8Encoding($false)))
    $TerminalFailureExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Read-GammaArenaGameTests.ps1') @('-LogPath', $TerminalFailureLog)
    Assert-True ($TerminalFailureExit -ne 0) 'Game-log reader must reject a test status after ALL PASS.'

    $FakeMo2Root = Join-Path $TempRoot 'fake-mo2'
    $UnsafeTarget = Join-Path $FakeMo2Root 'mods\Gamma Arena DEV'
    Write-FixtureFile $FakeMo2Root 'mods\Gamma Arena DEV' 'must not be replaced'
    $DeployExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Deploy-GammaArenaDev.ps1') @('-Mo2Root', $FakeMo2Root)
    Assert-True ($DeployExit -ne 0) 'Dev deployment must reject an existing non-directory target.'
    Assert-True (Test-Path -LiteralPath $UnsafeTarget -PathType Leaf) 'Dev deployment must preserve an existing non-directory target.'

    $ReparseMo2Root = Join-Path $TempRoot 'reparse-mo2'
    $ReparseTarget = Join-Path $ReparseMo2Root 'mods\Gamma Arena DEV'
    $ReparseDestination = Join-Path $TempRoot 'reparse-destination'
    New-Item -ItemType Directory -Path (Join-Path $ReparseMo2Root 'mods') -Force | Out-Null
    New-Item -ItemType Directory -Path $ReparseDestination -Force | Out-Null
    New-Item -ItemType Junction -Path $ReparseTarget -Target $ReparseDestination | Out-Null
    $ReparseDeployExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Deploy-GammaArenaDev.ps1') @('-Mo2Root', $ReparseMo2Root)
    Assert-True ($ReparseDeployExit -ne 0) 'Dev deployment must reject an existing reparse-point target.'
    Assert-True (((Get-Item -LiteralPath $ReparseTarget).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Dev deployment must preserve an existing reparse-point target.'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

Write-Host 'PASS: tool regression smoke checks passed'
