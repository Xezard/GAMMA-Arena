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
    'catalog_discovery_is_order_stable',
    'catalog_discovery_enumeration_failure_falls_back'
)) {
    if (-not $Tests.Contains($CaseName)) {
        throw "Dynamic catalog discovery test is missing: $CaseName"
    }
}

Write-Host 'PASS: dynamic catalog discovery static contract passed'
