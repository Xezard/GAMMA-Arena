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

    $ArenaScripts = @(Get-ChildItem -LiteralPath (Join-Path $SourceGamedata 'scripts') -Filter 'gamma_arena_*' -File -ErrorAction SilentlyContinue)
    foreach ($Script in $ArenaScripts) {
        Assert-True (-not (Test-TextPattern $Script.FullName '\bmath\.random(seed)?\b')) "Non-deterministic random call: $(Get-RelativeRepoPath $Script.FullName)"
    }

    $MutationNamePattern = '(?i)(spawn|give|remove|teleport|set|add|delete|replace|patch|inject|override|mutat)'
    foreach ($File in $AllSourceFiles) {
        if ($File.BaseName -match $MutationNamePattern) {
            Assert-True ($File.BaseName -match '^(gamma_arena|ga_)') "Mutation-oriented file must use gamma_arena or ga_ prefix: $(Get-RelativeRepoPath $File.FullName)"
        }
    }

    $CatalogFiles = @($AllSourceFiles | Where-Object { $_.Name -match '(?i)(npc.*catalog|catalog.*npc|npc_catalog)' })
    $MutantPattern = '(?i)\b(bloodsucker|boar|burer|cat|chimera|controller|dog|flesh|fracture|gigant|izlom|karlik|pseudodog|pseudogiant|psy[_-]?dog|snork|tushkano|zombie|mutant)\b'
    foreach ($Catalog in $CatalogFiles) {
        Assert-True (-not (Test-TextPattern $Catalog.FullName $MutantPattern)) "NPC catalog contains known mutant entry: $(Get-RelativeRepoPath $Catalog.FullName)"
    }

    $MenuXmlFiles = @($AllSourceFiles | Where-Object { $_.Name -match '(?i)(main.*menu|menu.*main)' -and $_.Extension -ieq '.xml' })
    foreach ($MenuXml in $MenuXmlFiles) {
        $MenuContent = Get-Content -LiteralPath $MenuXml.FullName -Raw
        $HasDxmlInsert = $MenuContent -match '(?i)dxml|insert'
        if ($HasDxmlInsert) {
            Assert-True ($MenuContent -match 'btn_gamma_arena') "DXML main-menu insert lacks btn_gamma_arena: $(Get-RelativeRepoPath $MenuXml.FullName)"
            Assert-True ($MenuContent -match '(?i)(not\s+.*btn_gamma_arena|btn_gamma_arena.*(not|exists|find|query)|duplicate)') "DXML main-menu insert lacks duplicate query guard: $(Get-RelativeRepoPath $MenuXml.FullName)"
        }
    }
}

$ReleaseFiles = @(Get-ChildItem -LiteralPath $RepoRoot -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '\\(\.git|dist|build|work)\\'
})
foreach ($File in $ReleaseFiles) {
    Assert-True ($File.Name -notmatch '(?i)^gamma_arena_test_') "Release source contains test fixture: $(Get-RelativeRepoPath $File.FullName)"
}

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

Write-Host 'PASS: static project checks passed'
